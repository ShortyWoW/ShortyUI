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

local lookup = {'Hunter-Survival','Hunter-Marksmanship','Druid-Balance','Druid-Restoration','Monk-Mistweaver','Monk-Windwalker','DeathKnight-Unholy','Unknown-Unknown','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Shaman-Restoration','Priest-Discipline','DemonHunter-Devourer','Paladin-Retribution','Hunter-BeastMastery','Priest-Holy','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Vengeance','DemonHunter-Havoc','Mage-Fire','Warrior-Fury','Shaman-Elemental','Warrior-Arms','Monk-Brewmaster','Mage-Arcane','Mage-Frost','Druid-Feral','DeathKnight-Blood','Druid-Guardian','Warrior-Protection','Rogue-Assassination','Rogue-Subtlety','Paladin-Protection','Paladin-Holy','Priest-Shadow','Evoker-Preservation','DeathKnight-Frost','Rogue-Outlaw','Shaman-Enhancement',}
local provider = {region='US',realm='Hellscream',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aarix:BAABLgAECn8kAAMBAAkJAQ5aCgD+AQABAAkJAQ5aCgD+AQACAAEJCgDAnAACAAAAAA==.',
Ac='Achmed:BAAALgAECgEJAQAAAA==.',
Ad='Adaptabull:BAABLgAECn8bAAMDAAgJShl2FQCTAQADAAgJShl2FQCTAQAEAAIJIxWyrgBoAAAAAA==.Adari:BAAALgADCgMJAwAAAA==.Adune:BAAALgADCgQJBAAAAA==.',
Ae='Aelinessa:BAAALgAECgcJDAAAAA==.Aelthalyste:BAAALgAECgYJAwAAAA==.Aeo:BAABLgAECn8bAAMFAAgJaxwPBwCMAgAFAAgJaxwPBwCMAgAGAAQJCARTOgCVAAABLgAECgkJKAAEABQgAA==.Aerodox:BAAALgAECgIJAgAAAA==.',
Ai='Aiel:BAAALgAECgcJEQABLgAECggJFQAHAKkUAA==.',
Al='Albedò:BAAALgAECgIJAwAAAA==.Aldrîch:BAAALgADCgMJAwAAAA==.Allyra:BAAALgADCgIJAgABLgAECgIJBQAIAAAAAA==.Allzaz:BAAALgAECgUJEgABLgAECggJIwAJALEWAA==.Allzera:BAABLgAECn8jAAQJAAgJsRbADgBEAQAKAAgJgxWZSABOAQAJAAcJChPADgBEAQALAAUJqxCGEgDBAAAAAA==.Alric:BAAALgAECgYJDAAAAA==.Altheus:BAAALgADCggJCAAAAA==.',
Am='Amalei:BAAALgADCgYJCQAAAA==.Amberness:BAAALgAECgIJAgABLgAFFAMJBwAMACseAA==.Ammaria:BAAALgADCgUJBQAAAA==.Amorose:BAAALgAECgcJCgAAAA==.',
An='Anastassia:BAAALgAECgMJAgABLgAECgkJKwANAKASAA==.Andol:BAAALgADCgUJBQABLgAECgcJEgAIAAAAAA==.Anduwyn:BAAALgADCgIJAgAAAA==.Anezra:BAAALgAECgEJAQAAAA==.Angelmack:BAAALgAECggJBwAAAA==.Anibella:BAABLgAECn8iAAIOAAgJYR0CGAD8AQAOAAgJYR0CGAD8AQAAAA==.Antons:BAAALgADCgkJEAAAAA==.Anuke:BAAALgAECgYJCgAAAA==.',
Ap='Aphlykted:BAAALgADCgYJBwAAAA==.',
Ar='Arbinu:BAAALgADCgMJAwAAAA==.Arflane:BAAALgADCgEJAQAAAA==.Argenta:BAAALgADCgEJAQAAAA==.Arkhlight:BAABLgAECn8XAAIPAAgJ8hz7HQATAgAPAAgJ8hz7HQATAgAAAA==.Arkhmonk:BAAALgAFFAEJAQAAAA==.Arkillos:BAAALgAECgEJAwAAAA==.Armerous:BAAALgADCgMJAwAAAA==.Arnlok:BAAALgADCgMJAwAAAA==.Arrowhoof:BAABLgAFFH8IAAIQAAIJCwjtGgCZAAAQAAIJCwjtGgCZAAAAAA==.Arthurian:BAAALgADCgUJEQAAAA==.',
As='Ashmorph:BAAALgADCgYJCAAAAA==.Ashpriest:BAABLgAECn8iAAMRAAgJmRmlEADiAQARAAgJKxmlEADiAQANAAQJ7RaSIwAOAQAAAA==.Ashýra:BAABLgAECn8nAAIRAAkJmw0XFQCuAQARAAkJmw0XFQCuAQAAAA==.Askellus:BAAALgADCgYJBgAAAA==.Asphyxxed:BAAALgAECgEJAQAAAA==.Asterisk:BAABLgAECn8xAAIQAAkJdR0iCgCVAgAQAAkJdR0iCgCVAgAAAA==.Asya:BAAALgAECgYJBQAAAA==.Asymmetric:BAAALgAECgkJBwAAAA==.',
At='Ataxica:BAAALgAECgEJAQAAAA==.Atlas:BAAALgAECgMJAwAAAA==.Attanu:BAAALgADCgIJAgAAAA==.Attilathepun:BAAALgADCgcJBwAAAA==.',
Au='Augrizia:BAAALgADCgMJBQAAAA==.Auriêl:BAAALgAECgQJBgAAAA==.',
Az='Azastra:BAABLgAECn8dAAMSAAcJygxzBwBBAQASAAcJygxzBwBBAQATAAYJbgedLwDnAAAAAA==.Azer:BAAALgADCgYJBgAAAA==.Azorian:BAAALgAECggJBwAAAA==.',
['Añ']='Aña:BAABLgAECn8cAAQUAAgJpCL5AwD8AQAUAAcJiiL5AwD8AQAOAAQJow6QhgCGAAAVAAQJSRqFMABnAAAAAA==.Añarchist:BAAALgADCggJFQABLgAECgkJHAAUAKQiAA==.',
Ba='Babyymonster:BAAALgAFFAEJAQAAAA==.Badboii:BAAALgADCgMJAwAAAA==.Baelzharon:BAABLgAECn8aAAIWAAcJshlnAgCfAQAWAAcJshlnAgCfAQAAAA==.Baerenger:BAAALgAECggJEwAAAA==.Baern:BAAALgAECgYJDwABLgAECggJEwAIAAAAAA==.Bagelpanda:BAAALgADCgMJAwAAAA==.Balròg:BAAALgADCgEJAQAAAA==.Barrthas:BAABLgAFFH8KAAIHAAQJuB6ZFQB9AQAHAAQJuB6ZFQB9AQAAAA==.Basalt:BAABLgAECn8iAAIQAAgJQxyxFwASAgAQAAgJQxyxFwASAgAAAA==.Bastenwode:BAAALgAECgQJCgAAAA==.',
Bb='Bbye:BAAALgAECgEJAQAAAA==.',
Be='Bearmyload:BAAALgADCgUJBQABLgAECgcJFAAHAEMhAA==.Beastwrld:BAAALgADCgcJGgAAAA==.Becký:BAABLgAECn8cAAIQAAgJyB4xGwD7AQAQAAgJyB4xGwD7AQAAAA==.Beeflomein:BAAALgADCgEJAQAAAA==.Beroan:BAAALgADCgYJBgAAAA==.',
Bi='Bigcøøkie:BAAALgADCgcJCAAAAA==.Bighealin:BAAALgAECgQJBgAAAA==.Bigjim:BAABLgAECn8WAAMKAAkJKx7wMwA8AgAKAAkJKx7wMwA8AgALAAEJNQRNbQA6AAAAAA==.Biglul:BAAALgAECgMJBAABLgAFFAQJEAAXAMkjAA==.Bigolcrities:BAAALgAECgIJAgAAAA==.Bivivi:BAAALgAECgYJDQAAAA==.',
Bj='Bjorn:BAAALgADCgQJBAAAAA==.',
Bl='Blackmagma:BAAALgAECgQJBQABLgAECggJGAAYAPMUAA==.Blackpiink:BAAALgAFFAEJAQAAAA==.Blackppink:BAACLgAFFH8LAAIMAAQJRxjnEAA7AQAMAAQJRxjnEAA7AQAuAAQKfyEAAgwACQlDHIcLAMYCAAwACQlDHIcLAMYCAAAA.Blackppinkk:BAAALgAFFAIJAgAAAA==.Bladefi:BAABLgAECn8dAAMVAAgJmiT6AwCRAgAVAAcJwiX6AwCRAgAOAAgJ8R1jPgD7AQAAAA==.Blamo:BAABLgAECn8iAAIEAAgJURbFGQD2AQAEAAgJURbFGQD2AQAAAA==.Blesedtogoon:BAAALgAECgMJBQAAAA==.Bloodbunny:BAAALgAECgUJCQAAAA==.Bluddbeard:BAAALgAECgkJCQAAAA==.',
Bm='Bmoneycuh:BAABLgAECn8fAAIKAAgJMB3oEgBLAgAKAAgJMB3oEgBLAgAAAA==.',
Bo='Boozerbear:BAAALgAECgkJAwAAAA==.Bornite:BAAALgADCgkJFQAAAA==.Bosstradamus:BAAALgAECgkJEAABLgAFFAIJAgAIAAAAAA==.Bottombenoit:BAAALgADCgYJCgAAAA==.',
Br='Brewmanfu:BAABLgAECn8xAAMFAAkJjxx0CgBFAgAFAAkJjxx0CgBFAgAGAAUJdQkMXQCcAAAAAA==.Brewmaster:BAAALgAECgEJAQAAAA==.Brickaton:BAABLgAECn8YAAIQAAcJ/xRkMwCAAQAQAAcJ/xRkMwCAAQAAAA==.Brickdrag:BAAALgADCgYJBgABLgAECgcJGAAQAP8UAA==.Brickpanda:BAAALgAECgMJAwAAAA==.Brionaimina:BAAALgADCgQJBAAAAA==.Brocknor:BAABLgAECn8iAAIZAAgJLxxbBABBAgAZAAgJLxxbBABBAgAAAA==.Brook:BAAALgADCgcJBwAAAA==.Brucebanners:BAAALgAECgEJAgABLgAFFAQJBwAOAFYMAA==.Bruiseli:BAABLgAECn8cAAMaAAcJ6AMHMQDXAAAaAAcJ6AMHMQDXAAAGAAMJTALEbwBTAAAAAA==.Brujilda:BAAALgAECgYJDgABLgAECgcJFAAPADQIAA==.Brèdren:BAACLgAFFH8HAAIFAAQJnBQWEAAfAQAFAAQJnBQWEAAfAQAuAAQKf0oAAgUACQmaIiUBAIoDAAUACQmaIiUBAIoDAAAA.Brüh:BAAALgAECggJDAAAAA==.',
Bu='Bucklebury:BAAALgADCgEJAQAAAA==.Bullogna:BAAALgAECgIJAgAAAA==.Burbon:BAAALgADCgYJCAABLgAECggJJAAGAAMjAA==.Burstinatrix:BAAALgADCgEJAQAAAA==.Burtina:BAAALgAECgEJAQAAAA==.Butterdtoast:BAEBLgAECn8YAAIGAAgJehIBEwCcAQAGAAgJehIBEwCcAQAAAA==.',
['Bë']='Bëâst:BAAALgAECgIJAgAAAA==.',
Ca='Caboose:BAABLgAECn8hAAQbAAgJRR6WAgBqAgAbAAcJRR6WAgBqAgAcAAMJaApqGgHKAAAWAAMJgBFQCQC+AAAAAA==.Cadius:BAAALgADCgMJAwAAAA==.Caimera:BAAALgAECgEJAQAAAA==.Caledor:BAAALgAECgMJBAAAAA==.Calindrel:BAABLgAECn8YAAIXAAgJ3gNjMAAKAQAXAAgJ3gNjMAAKAQAAAA==.Calita:BAAALgADCgYJBgAAAA==.Caraway:BAAALgAECgUJBQAAAA==.Carcus:BAAALgADCggJCAAAAA==.Carysa:BAAALgADCgcJFAAAAA==.',
Ce='Celebrindal:BAAALgADCgkJHQAAAA==.Celson:BAAALgADCgIJAQAAAA==.Celticlore:BAAALgAECgIJAgAAAA==.Cerrvantes:BAAALgADCgMJAwAAAA==.Cesarius:BAAALgAECgYJEwAAAA==.',
Ch='Chalida:BAAALgADCgkJCQAAAA==.Chappellroan:BAAALgAECgQJBAAAAA==.Charlemange:BAAALgADCgMJAwAAAA==.Charvein:BAAALgAECgQJBAAAAA==.Chernaboz:BAABLgAECn8ZAAILAAgJsRTKBAC5AQALAAgJsRTKBAC5AQAAAA==.Chevelot:BAAALgADCgYJDAAAAA==.Chibbo:BAABLgAECn8fAAIdAAkJJQhBCQCUAQAdAAkJJQhBCQCUAQAAAA==.Chiblet:BAAALgAECgIJAgAAAA==.Chillblain:BAAALgADCgEJAQAAAA==.Chippendale:BAAALgADCgkJGwAAAA==.Chondre:BAABLgAECn8eAAIKAAgJfR9sFgAvAgAKAAgJfR9sFgAvAgAAAA==.Chrigs:BAAALgAECgYJBwAAAA==.Chrispbacon:BAAALgADCgYJBgAAAA==.',
Ci='Citrogen:BAAALgAECgUJBQAAAA==.',
Cl='Clickityclak:BAAALgADCgIJAgAAAA==.',
Co='Colin:BAAALgADCgMJAgABLgAECgkJCgAIAAAAAA==.Combustdeez:BAAALgADCgUJBQABLgAFFAgJEQAKAFUgAA==.Conrad:BAAALgADCgUJBQAAAA==.Copperheadj:BAAALgAECgMJAwABLgAECgcJFAAHAKUJAA==.Copperknight:BAABLgAECn8UAAIHAAcJpQn4fADnAAAHAAcJpQn4fADnAAAAAA==.Corenthos:BAABLgAECn8qAAMHAAgJ6yGrDQCWAgAHAAgJ6yGrDQCWAgAeAAEJuRvkMQBQAAAAAA==.Cornelia:BAAALgAECgQJBAABLgAECgkJKwANAKASAA==.Cortanna:BAAALgADCgYJDgAAAA==.',
Cr='Cranker:BAAALgAECgMJCwAAAA==.Crashedot:BAAALgAECgQJBwAAAA==.Crazymoron:BAAALgADCggJCAAAAA==.Creselia:BAABLgAECn8YAAIcAAYJFQqtgAAQAQAcAAYJFQqtgAAQAQAAAA==.Criminel:BAAALgADCgEJAQAAAA==.Cropduzzter:BAAALgADCgQJBAAAAA==.Crum:BAABLgAECn8bAAMDAAgJlgjNIwAbAQADAAgJfwjNIwAbAQAfAAMJ9wTxJQBBAAAAAA==.Cryptnotic:BAAALgADCgIJAgAAAA==.',
Cu='Cuddlerz:BAAALgAECgIJAgAAAA==.Cutthrøat:BAAALgAECgQJBgAAAA==.',
Cy='Cypherrellik:BAAALgAECgcJEAABLgAECgcJFQAVAJsQAA==.',
['Câ']='Câp:BAAALgAECgcJCAAAAA==.',
Da='Dablackmasta:BAABLgAECn8XAAIXAAgJbQ7ZJQBFAQAXAAgJbQ7ZJQBFAQAAAA==.Daftfunk:BAAALgADCggJCAAAAA==.Dagthunderer:BAAALgAECgYJCwAAAA==.Daidonks:BAAALgAECgMJBAAAAA==.Dakkenrahl:BAAALgAECgUJDQAAAA==.Dalistra:BAAALgAECgIJBQAAAA==.Dalweaver:BAAALgAECgEJAgABLgAECgIJBQAIAAAAAA==.Dalzz:BAAALgADCgYJBgABLgAECgIJBQAIAAAAAA==.Dantar:BAAALgADCgQJBAAAAA==.Dantes:BAAALgADCgkJFAAAAA==.Dar:BAAALgAECgUJCQAAAA==.Darkaires:BAAALgAECgkJBgAAAA==.Darkflame:BAABLgAECn8XAAIQAAgJwxjMGQAEAgAQAAgJwxjMGQAEAgAAAA==.Darksidedbro:BAAALgADCgkJEQAAAA==.Darthvaeder:BAAALgAECgUJDAAAAA==.Davee:BAAALgADCgcJBwAAAA==.',
Dc='Dcpt:BAAALgADCgcJFAAAAA==.',
De='Deadgeinside:BAAALgAECgYJCgAAAA==.Deadgnome:BAAALgAECgIJAgABLgAECggJHgAaAFAQAA==.Deathrose:BAAALgADCgkJCgAAAA==.Deathstomper:BAAALgAECgQJBgAAAA==.Delnarian:BAABLgAECn8jAAIPAAgJyB0RFwBCAgAPAAgJyB0RFwBCAgAAAA==.Demondono:BAABLgAECn8hAAIVAAgJ8RLVDACzAQAVAAgJ8RLVDACzAQAAAA==.Demonsnake:BAAALgADCgEJAQAAAA==.Desmorphia:BAAALgAECgEJAgAAAA==.Destruir:BAAALgADCgkJCgAAAA==.Desy:BAAALgADCgQJBAABLgAECggJFwAKAIIiAA==.Dethomonic:BAAALgADCgkJCQAAAA==.Devomo:BAABLgAECn8qAAIOAAcJSSJeEgAqAgAOAAcJSSJeEgAqAgAAAA==.Devoutsquirl:BAAALgADCgYJBgABLgAECggJFQAgAAEgAA==.Deyedora:BAAALgAECgcJDAAAAA==.Deyjavaknadi:BAAALgADCgMJAwAAAA==.',
Di='Diegodruida:BAAALgADCgUJBQAAAA==.Dilligafnope:BAAALgADCgkJGwAAAA==.Dinkster:BAABLgAECn8bAAMDAAgJNgv6HABNAQADAAgJNgv6HABNAQAEAAMJ0gSJsABkAAAAAA==.Dinohunter:BAABLgAECn8bAAIQAAgJHCJRCACtAgAQAAgJHCJRCACtAgAAAA==.Dinokat:BAAALgADCgUJBgABLgAECgkJLQAKAPsXAA==.Dirtslinger:BAAALgAECgUJCAAAAA==.Disabler:BAACLgAFFH8RAAMKAAgJVSAeAADaAgAKAAgJVSAeAADaAgALAAEJBxU1EQBVAAAuAAQKfyUAAwoACQlBJpwAAH8DAAoACQlBJpwAAH8DAAsAAQnvIdJZAGEAAAAA.Discotits:BAAALgAECgEJAQAAAA==.',
Do='Dobyclease:BAAALgAECgMJAwAAAA==.Dojob:BAAALgADCgEJAQAAAA==.Dokesa:BAABLgAECn8WAAMHAAcJ0R3eQwAqAgAHAAYJQyHeQwAqAgAeAAEJlwzlRwApAAAAAA==.Dolfratt:BAAALgAECggJEAABLgAECgkJMQAFAI8cAA==.Dooknukem:BAAALgADCgYJBgAAAA==.Doomguard:BAAALgAECgMJAwAAAA==.Dorimane:BAAALgAECggJFQAAAQ==.Dorimonk:BAAALgAECgEJAQABLgAECggJFQAIAAAAAQ==.Dorlock:BAABLgAECn8fAAIJAAcJNAhnCAAXAQAJAAcJNAhnCAAXAQAAAA==.Dortivi:BAAALgAECgUJBQAAAA==.Dotdôtdot:BAAALgADCgIJAgAAAA==.Dotrastraez:BAAALgADCgIJAgAAAA==.Dotvader:BAAALgAECgcJDQAAAA==.',
Dr='Dragonrend:BAAALgAECgMJAwAAAA==.Draklee:BAAALgAECgEJAgAAAA==.Draxestraza:BAAALgADCgcJFwAAAA==.Draykey:BAAALgAECgQJBQABLgAECggJKgAEABodAA==.Draykeyy:BAABLgAECn8qAAIEAAgJGh3aFgAOAgAEAAgJGh3aFgAOAgAAAA==.Dred:BAAALgAECgEJAQAAAA==.Dreddk:BAAALgADCgIJAgAAAA==.Dredwarrior:BAABLgAECn8aAAMZAAkJsBEdFQARAQAXAAYJ+xACXgA3AQAZAAYJog4dFQARAQAAAA==.Drenlei:BAAALgAECgcJBwABLgAECggJJwAOACcXAA==.Drood:BAAALgAECgEJAQAAAA==.Drotara:BAABLgAECn8cAAMQAAgJbx0hDgBoAgAQAAgJbx0hDgBoAgABAAMJ3xP1IQDtAAAAAA==.Drprodigy:BAABLgAECn8iAAIOAAkJzRRWPAADAgAOAAkJzRRWPAADAgAAAA==.Drunkbaby:BAACLgAFFH8GAAIPAAMJux3SHwAvAQAPAAMJux3SHwAvAQAuAAQKfxQAAg8ACQnwIKcRAAQDAA8ACQnwIKcRAAQDAAAA.',
Du='Dukkha:BAAALgADCgcJBQAAAA==.',
Dy='Dynasty:BAAALgAECgQJBwAAAA==.Dyrcyn:BAAALgAECgEJAQAAAA==.',
['Dà']='Dàddy:BAAALgAECgMJAwAAAA==.Dànger:BAAALgAECgkJCgAAAA==.',
Ed='Edrius:BAAALgAECgUJBQAAAA==.Edroh:BAABLgAECn8hAAIcAAgJJwl8VQBsAQAcAAgJJwl8VQBsAQAAAA==.',
Eh='Ehsera:BAAALgADCgUJBgAAAA==.',
Ei='Eidur:BAABLgAECn8YAAMhAAkJAhmgBwBkAQAhAAkJshigBwBkAQAiAAUJ7BZaPAA4AQAAAA==.',
El='Elando:BAAALgAECgQJBAAAAA==.Elegies:BAACLgAFFH8FAAIOAAMJygYfPgC1AAAOAAMJygYfPgC1AAAuAAQKfzwAAg4ACQkzIO8HAKYCAA4ACQkzIO8HAKYCAAAA.Elemefayoh:BAAALgAECgQJBQABLgAECgYJCQAIAAAAAA==.Elfater:BAAALgAECgMJAwAAAA==.Eliarace:BAAALgADCgMJAwAAAA==.Eljeffesan:BAAALgADCgcJFwAAAA==.Elspeth:BAAALgADCgYJBgABLgAECggJHAAQAG8dAA==.Elythria:BAAALgAECgQJBwAAAA==.',
Em='Emagonadye:BAACLgAFFH8OAAIaAAQJxhsjCQBxAQAaAAQJxhsjCQBxAQAuAAQKfxgAAxoACAm2JFMEAEcDABoACAm2JFMEAEcDAAYAAQm+HWFLAFcAAAAA.Emerey:BAAALgADCgIJAQAAAA==.Emlee:BAAALgADCgIJAgAAAA==.Emporersmaug:BAAALgADCgEJAQAAAA==.',
En='Endgamer:BAAALgAECgYJBgAAAA==.Endugu:BAABLgAECn8XAAIcAAgJ3A5SRwCRAQAcAAgJ3A5SRwCRAQAAAA==.Enflamee:BAABLgAECn8dAAMcAAgJ6yJFCwDIAgAcAAgJ6yJFCwDIAgAbAAEJUwzOHQA2AAAAAA==.Enforcer:BAABLgAECn8cAAMKAAgJvxt8OQCAAQAKAAcJeRp8OQCAAQALAAMJBRXaOgDJAAAAAA==.Engath:BAAALgAECgYJDAABLgAECggJHQAcAOsiAA==.',
Er='Erikprince:BAAALgADCgEJAgAAAA==.Erosonia:BAAALgAECgQJDQAAAA==.Erso:BAAALgADCgYJCAAAAA==.',
Es='Espresso:BAAALgAECgcJEAAAAA==.',
Et='Eternalpaín:BAACLgAFFH8GAAIPAAIJUxRJPgCwAAAPAAIJUxRJPgCwAAAuAAQKfyMAAg8ACAlEHLwlAOsBAA8ACAlEHLwlAOsBAAAA.',
Ev='Evanee:BAABLgAECn8VAAIMAAgJdRhWHwC4AQAMAAgJdRhWHwC4AQAAAA==.Evanrude:BAAALgAECgQJBAAAAA==.',
Ez='Ezykeul:BAAALgAECgUJDQAAAA==.',
Fa='Fal:BAABLgAECn8WAAMQAAkJNhF/TwB6AQAQAAgJVxF/TwB6AQACAAUJUAgCWwDXAAAAAA==.Falcyon:BAAALgADCgMJAwAAAA==.Fallenson:BAAALgAECgEJAwAAAA==.',
Fe='Felbrooks:BAAALgADCgkJFQAAAA==.Felmommy:BAAALgADCgcJAQAAAA==.Felsông:BAAALgADCgcJBwAAAA==.Fendretta:BAABLgAECn8hAAIQAAgJpxYPIADcAQAQAAgJpxYPIADcAQAAAA==.',
Fi='Firefawkes:BAAALgAECgUJBQAAAA==.Fistbump:BAAALgADCgYJDAAAAA==.Fivepiece:BAAALgADCgcJBwAAAA==.Fixzie:BAABLgAECn8aAAIXAAgJag6ZGACiAQAXAAgJag6ZGACiAQAAAA==.',
Fl='Flah:BAAALgAFFAEJAQAAAA==.Flip:BAAALgAECgcJBwAAAA==.Flizrak:BAABLgAECn8aAAIXAAgJkSPtBQCVAgAXAAgJkSPtBQCVAgABLgAFFAcJGwAcAAwdAA==.',
Fo='Footsteps:BAAALgAECgYJBgAAAA==.Forestflex:BAAALgAECgYJBgAAAA==.Foxstrazagos:BAAALgADCgkJCwAAAA==.',
Fr='Freakopath:BAAALgAECgQJCAAAAA==.Friggnar:BAAALgADCgYJBwAAAA==.Frostsalad:BAAALgADCgQJBAAAAA==.Frostynugz:BAAALgADCgYJCQAAAA==.',
Fu='Fulta:BAABLgAECn8lAAICAAgJNhzcAwAOAgACAAgJNhzcAwAOAgAAAA==.',
Fy='Fyra:BAAALgAECgIJAgABLgAFFAQJCgAPAM8FAA==.',
['Fí']='Fírnen:BAAALgAECgQJBwAAAA==.',
Ga='Gailz:BAAALgADCgQJBAAAAA==.Galadoril:BAAALgADCgIJAgAAAA==.Gammb:BAAALgAECgEJAQAAAA==.Garadin:BAABLgAECn8gAAIDAAgJTxIuFAChAQADAAgJTxIuFAChAQAAAA==.Garcona:BAAALgAFFAIJBAAAAA==.Garnok:BAAALgAECgEJAQAAAA==.Garqman:BAAALgADCgUJBQAAAA==.Garwa:BAAALgAECgQJDQAAAA==.',
Ge='Geniver:BAAALgAECgUJDAAAAA==.Gerken:BAAALgAECgIJAgAAAA==.Gerkenator:BAAALgAECgYJCQAAAA==.Gerla:BAABLgAECn8aAAMPAAgJchFWSQBpAQAPAAcJBhRWSQBpAQAjAAgJkgYsFQD4AAAAAA==.',
Gh='Ghettoshout:BAAALgAECgMJBAAAAA==.',
Gi='Gialania:BAABLgAECn8gAAMDAAgJlAqmHABPAQADAAgJlAqmHABPAQAEAAMJjAB34wAiAAAAAA==.Gilgameshh:BAAALgADCgkJEQAAAA==.Girthbrook:BAAALgADCgcJCAAAAA==.Girthbrooks:BAAALgADCgQJBAAAAA==.Girthtrude:BAABLgAECn8jAAIOAAkJsw13JwCeAQAOAAkJsw13JwCeAQAAAA==.',
Gl='Glaivertoss:BAAALgAECggJCgAAAA==.Glorythighs:BAAALgADCgEJAQAAAA==.Glycerol:BAAALgADCgUJBQAAAA==.',
Go='Goblincox:BAAALgAECgYJEgAAAA==.Gomory:BAAALgAECgUJDAAAAA==.Gondark:BAAALgAECgQJBwAAAA==.Goobly:BAABLgAECn8cAAIiAAYJsReRLACaAQAiAAYJsReRLACaAQAAAA==.Gooseblade:BAAALgADCgUJBQAAAA==.Goregrimm:BAAALgAECgUJCQAAAA==.Gorgoz:BAAALgADCgEJAQAAAA==.Gorgrim:BAAALgADCgMJAwAAAA==.',
Gr='Gregòr:BAAALgAECgkJBQAAAA==.Gretchen:BAABLgAECn83AAMHAAgJ/RnkGwAhAgAHAAgJ/RnkGwAhAgAeAAQJbAisNgCMAAAAAA==.Greywing:BAAALgAECgYJCwAAAA==.Greywolf:BAABLgAECn8hAAIMAAkJWxmwFwBYAgAMAAkJWxmwFwBYAgAAAA==.Grezin:BAAALgADCgEJAQABLgAECgQJBwAIAAAAAA==.Grimlight:BAABLgAFFH8LAAIPAAQJ4SAoDAB6AQAPAAQJ4SAoDAB6AQABLgAFFAgJFgAHAP8XAA==.Grimshaw:BAAALgAECgYJBgAAAA==.Grimtorr:BAAALgADCgMJAwAAAA==.Ground:BAAALgAECgYJCQAAAA==.Grymlee:BAAALgAECgQJCwAAAA==.Grëgor:BAAALgAECgQJBAAAAA==.',
Gu='Guinènvere:BAAALgAECgYJEAAAAA==.',
['Gä']='Gärry:BAAALgAECgEJAQAAAA==.',
['Gö']='Gökù:BAAALgAECgEJAQAAAA==.',
Ha='Haedes:BAAALgAECgQJBAABLgAECgYJFAAFAFQRAA==.Haktori:BAAALgAECgYJDQAAAA==.Hammerknee:BAABLgAECn8WAAMkAAgJtRhVKgDfAQAkAAgJtRhVKgDfAQAPAAIJyAtHvwB2AAAAAA==.Hariku:BAAALgAECgQJCQAAAA==.Harleii:BAAALgAECgcJDgAAAA==.Harlequins:BAAALgAECgEJAwAAAA==.Harmonix:BAAALgAECgkJBgAAAA==.Harrow:BAAALgAECgYJCwAAAA==.Hastler:BAAALgADCgkJCQAAAA==.Hatthorned:BAAALgADCgEJAQAAAA==.Hawt:BAAALgAECgEJBQAAAA==.Haxx:BAAALgAECgEJAQAAAA==.',
He='Hearge:BAABLgAECn8dAAMkAAkJzBtWDQCuAgAkAAkJzBtWDQCuAgAPAAYJVQgRuwAQAQAAAA==.Heckatae:BAABLgAECn8UAAIcAAYJ0QlzfwASAQAcAAYJ0QlzfwASAQAAAA==.Hellborne:BAAALgADCgIJAgAAAA==.Hellhawk:BAABLgAECn8ZAAIkAAgJYhRAFADwAQAkAAgJYhRAFADwAQAAAA==.Helwe:BAAALgAECgMJBQAAAA==.Heptandew:BAAALgAECgYJCAAAAA==.Hexmon:BAAALgAECgEJAgAAAA==.',
Hi='Hikkio:BAAALgADCgMJAwAAAA==.',
Ho='Holycheeks:BAAALgADCgYJBgAAAA==.Holychib:BAAALgAECgYJCAAAAA==.Holypho:BAAALgADCgYJDAAAAA==.Holysheet:BAAALgAECgYJCAAAAA==.Holystan:BAAALgAECgYJEwAAAA==.Hondoe:BAAALgAECgQJBQAAAA==.Honorable:BAAALgADCgEJAQABLgAECgkJMQAFAI8cAA==.Hoshino:BAAALgAECgEJAgABLgAECgYJDgAIAAAAAA==.Hoshiyoru:BAAALgADCggJFAAAAA==.Houki:BAABLgAECn8eAAIPAAgJpwj6WgA6AQAPAAgJpwj6WgA6AQAAAA==.',
Hp='Hpylorii:BAAALgAECgYJEgAAAA==.',
Ht='Htownhunter:BAAALgAECgQJBwAAAA==.Htownprot:BAABLgAFFH8GAAIPAAQJEiBhDAB4AQAPAAQJEiBhDAB4AQAAAA==.',
Hu='Hungovertank:BAACLgAFFH8XAAIaAAYJJiKbAgDSAQAaAAYJJiKbAgDSAQAuAAQKfzEAAhoACAmIJREEAEwDABoACAmIJREEAEwDAAAA.Hungzilla:BAABLgAECn8iAAMTAAkJyRwOBADDAgATAAkJyRwOBADDAgASAAMJvw+1LgCiAAAAAA==.Huntered:BAAALgADCgMJAgAAAA==.Huntfromhell:BAABLgAECn8ZAAMUAAgJcCC/AgBEAgAUAAcJ5CG/AgBEAgAVAAYJURwYDgCfAQAAAA==.Hurkano:BAAALgADCgUJCQAAAA==.',
Ig='Ignisfatuus:BAAALgAECgcJEAAAAA==.',
Ik='Ikurei:BAAALgADCggJCAAAAA==.',
Il='Ilarion:BAAALgAECgQJBAAAAA==.Illio:BAAALgAECgUJCAAAAA==.Illyasviel:BAAALgAECgEJAwAAAA==.',
Im='Imarea:BAABLgAECn8cAAIcAAcJewaSewAaAQAcAAcJewaSewAaAQAAAA==.Impirious:BAABLgAECn8iAAMeAAgJhwl6GAAIAQAeAAgJhwl6GAAIAQAHAAQJpQZ56ACvAAAAAA==.Imppimp:BAAALgAECgYJCAAAAA==.Imtryntotank:BAABLgAECn8kAAIkAAgJPAskJgBZAQAkAAgJPAskJgBZAQAAAA==.Imyx:BAABLgAECn8dAAIHAAcJEBduOQCUAQAHAAcJEBduOQCUAQAAAA==.',
In='Infamuspikel:BAABLgAECn8UAAMHAAkJGhhSZQDEAQAHAAkJsRNSZQDEAQAeAAMJPBy/GgDwAAAAAA==.Infel:BAAALgAECgkJDQAAAA==.Inkkish:BAAALgAECgYJDgAAAA==.Innovates:BAAALgAECgQJDAAAAA==.Innowar:BAAALgADCgYJBgAAAA==.Interstellar:BAAALgAECgYJBgAAAA==.Intervene:BAAALgADCgMJAwABLgAFFAIJBgAPAFMUAA==.Invictus:BAABLgAECn8dAAIcAAgJSg1OSgCJAQAcAAgJSg1OSgCJAQAAAA==.',
Io='Iota:BAAALgAECgYJEwAAAA==.',
Ir='Irminarae:BAABLgAECn8iAAMKAAgJ6Q6+NQCOAQAKAAgJ6Q6+NQCOAQALAAEJPgM2egAoAAAAAA==.',
Is='Isa:BAAALgADCgEJAQAAAA==.Isaßeau:BAAALgAECggJEAAAAA==.',
Ja='Jandoar:BAABLgAECn8dAAIcAAcJWgVJgAARAQAcAAcJWgVJgAARAQAAAA==.Jarlen:BAAALgADCgcJDAAAAA==.Jasmil:BAAALgADCgUJCAAAAA==.Jaylah:BAAALgADCgUJBgAAAA==.',
Je='Jeohr:BAAALgAECgEJAQAAAA==.Jezala:BAAALgADCgkJIgAAAQ==.',
Ji='Jiq:BAAALgADCgUJBwAAAA==.',
Jo='Johli:BAAALgADCgkJCQAAAA==.',
['Jö']='Jördyn:BAAALgADCgcJCgAAAA==.',
Ka='Kabilos:BAAALgAECgcJEAAAAA==.Kaboòm:BAACLgAFFH8FAAIcAAMJwgdSUQDdAAAcAAMJwgdSUQDdAAAuAAQKfyEAAhwACAlxEKZ9ANYBABwACAlxEKZ9ANYBAAAA.Kaedian:BAAALgADCgQJBAABLgAECggJJAAGAAMjAA==.Kaelthazad:BAAALgADCgEJAQAAAA==.Kagamai:BAAALgADCgUJBQAAAA==.Kagaramar:BAAALgAECgEJAQAAAA==.Kalesmora:BAABLgAECn8fAAIZAAgJ1Bp5BAA8AgAZAAgJ1Bp5BAA8AgAAAA==.Kaluu:BAAALgAECgEJAQABLgAECgEJAgAIAAAAAA==.Kamikaze:BAABLgAECn8hAAIVAAgJWRAPDwCQAQAVAAgJWRAPDwCQAQAAAA==.Kaorî:BAAALgADCgEJAQAAAA==.Karlov:BAABLgAECn8QAAIlAAcJBhPQJQCpAQAlAAcJBhPQJQCpAQAAAA==.Karthis:BAAALgAECgEJAQAAAA==.Kassima:BAAALgADCgEJAQAAAA==.Katebush:BAAALgAECgIJAgAAAA==.Kaydahlia:BAAALgAECgQJBQAAAA==.',
Ke='Keelmyeve:BAAALgAECgQJBwAAAA==.Keheo:BAAALgAECgEJAQAAAA==.Kelastalan:BAAALgADCgIJAgAAAA==.Kelithiena:BAAALgADCgYJDgAAAA==.Keynn:BAAALgADCgIJAgABLgAECggJJAAGAAMjAA==.',
Kh='Khaziel:BAAALgAECgUJBQAAAA==.Kheims:BAAALgAECgQJBAAAAA==.Khri:BAAALgAECgIJAgAAAA==.Khuzdul:BAAALgAECgEJAQAAAA==.',
Ki='Kidcat:BAAALgAECgMJBQAAAA==.Kiddemon:BAAALgADCgcJCAAAAA==.Killduran:BAAALgAFFAIJAgAAAA==.Kimiyo:BAAALgADCgcJCAAAAA==.Kimpossumble:BAAALgAECgMJAwAAAA==.Kinetic:BAAALgADCgkJEAAAAA==.Kirasha:BAAALgADCgIJAgAAAA==.',
Kl='Kleopatra:BAABLgAECn8gAAMGAAYJlgk7OACfAAAGAAYJxwU7OACfAAAaAAQJJAuxRwB2AAAAAA==.Klunt:BAAALgADCgcJCAABLgAECgcJFgASAPIdAA==.',
Kn='Knitehunt:BAAALgAECgUJBQAAAA==.Knives:BAAALgAECgQJCwAAAA==.',
Ko='Kochiyo:BAAALgADCgcJFwAAAA==.Korgal:BAAALgAECgIJAgAAAA==.Kortar:BAAALgAECgQJBAAAAA==.Kotros:BAAALgAECgcJDgAAAA==.',
Kr='Kracked:BAAALgAECgMJBAABLgAECgYJEwAIAAAAAA==.Kreigan:BAAALgADCgkJCQAAAA==.Krelid:BAAALgADCgkJEAABLgAECgcJHAAFAPsfAA==.Krellyroll:BAABLgAECn8cAAMFAAcJ+x9qCABuAgAFAAcJ+x9qCABuAgAGAAIJZRMhZAB9AAAAAA==.Krelthyr:BAAALgADCgkJDwABLgAECgcJHAAFAPsfAA==.Krumm:BAABLgAECn8pAAIgAAgJ2gl+EwAxAQAgAAgJ2gl+EwAxAQAAAA==.Krumpas:BAAALgADCgcJDgAAAA==.Kryvea:BAAALgADCggJCAAAAA==.',
Ku='Kuhne:BAAALgAECgMJAwAAAA==.Kurno:BAAALgAECgEJAQAAAA==.Kuromie:BAAALgADCgIJAgABLgAFFAEJAQAIAAAAAA==.',
Ky='Kyboom:BAAALgADCgYJBgAAAA==.',
['Kà']='Kàlluu:BAAALgAECgEJAgAAAA==.',
['Kñ']='Kñightboat:BAAALgAECgYJEgAAAA==.',
La='Ladeiene:BAAALgAECgIJAgAAAA==.Laelwyn:BAAALgAECgUJCwAAAA==.Laelynd:BAAALgADCgYJBgAAAA==.Lardna:BAAALgAECgEJAQAAAA==.',
Le='Leathermommy:BAAALgAECgcJEwAAAA==.Leges:BAABLgAECn8jAAMKAAgJnyOtBgDZAgAKAAgJnyOtBgDZAgALAAEJAACMMgAAAAAAAA==.Lehong:BAABLgAECn8jAAMaAAgJzBsaCQA1AgAaAAgJzBsaCQA1AgAGAAEJWgfXgwAsAAAAAA==.Lejion:BAAALgAFFAIJAwAAAA==.Lethariel:BAAALgAECgYJCQAAAA==.Lethas:BAABLgAECn8YAAIHAAgJHRy6GAA4AgAHAAgJHRy6GAA4AgAAAA==.',
Li='Liandrys:BAAALgAECgEJAwAAAA==.Lightrising:BAAALgAECgIJBAAAAA==.Lilfreya:BAAALgADCgQJBAAAAA==.Lilmonstrman:BAABLgAECn8lAAMcAAgJWBS/OAC/AQAcAAgJWBS/OAC/AQAbAAYJzhHRCABjAQAAAA==.Limbbiscuit:BAAALgAECgQJBAAAAA==.Linger:BAABLgAECn8XAAIHAAgJ4hgQWwAwAQAHAAgJ4hgQWwAwAQAAAA==.Linnet:BAAALgAECgEJAQAAAA==.Litany:BAABLgAECn8oAAIkAAgJvxAKGgC6AQAkAAgJvxAKGgC6AQAAAA==.Liya:BAABLgAECn8dAAMJAAgJ8RG6CgCQAQAJAAYJsRW6CgCQAQAKAAYJ1wlVaAD8AAAAAA==.',
Lo='Lokith:BAAALgAECgEJAQAAAA==.Lorilai:BAAALgAECgQJCAAAAA==.Loroke:BAAALgADCgkJCwAAAA==.Lots:BAAALgAECgQJBQAAAA==.Loxx:BAAALgAECgEJAgAAAA==.',
Lu='Lucith:BAAALgADCgcJCQAAAA==.Lul:BAACLgAFFH8QAAIXAAQJySOXAgCmAQAXAAQJySOXAgCmAQAuAAQKfyMAAxcABwmhI2kQAM4CABcABwmZI2kQAM4CABkABgltHbsKAPgBAAAA.Lumpthumb:BAAALgADCgMJAwAAAA==.Lunaaru:BAAALgAECgMJAwABLgAECgkJKAAEABQgAA==.Lunamay:BAABLgAECn8oAAMEAAkJFCByDwC9AgAEAAkJFCByDwC9AgADAAQJSA7FOwCYAAAAAA==.',
['Lð']='Lðvergirl:BAAALgAECgYJDAAAAA==.',
['Lò']='Lòck:BAAALgAECgEJAQAAAA==.',
['Ló']='Lóki:BAAALgADCgEJAQAAAA==.',
Ma='Machotaco:BAAALgADCgMJAwAAAA==.Maddieketh:BAAALgADCgMJAwAAAA==.Maeghor:BAACLgAFFH8FAAIcAAMJlwMfUwDTAAAcAAMJlwMfUwDTAAAuAAQKfxsAAhwABwlZF4CFAMYBABwABwlZF4CFAMYBAAAA.Maelleam:BAAALgAECgQJBAAAAA==.Maelsham:BAAALgADCgcJBwAAAA==.Magicash:BAAALgAECgYJDgAAAA==.Magistella:BAAALgAECgYJBgAAAA==.Magmadh:BAAALgAECgEJAwAAAA==.Malignantt:BAABLgAECn8bAAIeAAgJ8wyFFgAdAQAeAAgJ8wyFFgAdAQAAAA==.Manastress:BAAALgAECgQJBQAAAA==.Mapletoast:BAAALgADCgQJBAAAAA==.Mareanette:BAAALgAECgEJAQABLgAECggJHgAaAFAQAA==.Maskerade:BAAALgADCgUJBQAAAA==.Maurphious:BAAALgAECgMJAwAAAA==.Mavraela:BAAALgADCgYJEQAAAA==.',
Me='Meenhoe:BAAALgADCgUJBQAAAA==.Melee:BAAALgADCgcJBwAAAA==.Meleena:BAAALgADCgEJAQAAAA==.Melinola:BAAALgAECgMJBQAAAA==.Mellecarde:BAAALgAECgEJAQAAAA==.Melodrama:BAAALgAECgIJAwAAAA==.Messadin:BAABLgAECn8ZAAIjAAcJ7hbrDwA8AQAjAAcJ7hbrDwA8AQAAAA==.Metalguard:BAAALgADCgUJBQAAAA==.Methodical:BAAALgADCgEJAQAAAA==.Metri:BAAALgAECgUJDgAAAA==.',
Mi='Michelleyeoh:BAAALgADCgUJBQABLgAECgcJDgAIAAAAAA==.Michelney:BAAALgAECgUJBQAAAA==.Mikearoni:BAABLgAECn8nAAMTAAgJjxRlEwCuAQATAAgJjxRlEwCuAQAmAAEJeAH1TQAkAAAAAA==.Mirgaree:BAABLgAECn8ZAAIHAAgJFBBPOACYAQAHAAgJFBBPOACYAQAAAA==.Mistweaving:BAACLgAFFH8WAAIFAAUJDiWJAwASAgAFAAUJDiWJAwASAgAuAAQKfyMAAwUACAlMI0sGAPoCAAUACAlMI0sGAPoCAAYABAnNFQxMAOIAAAAA.',
Mo='Moistweaver:BAABLgAECn8eAAIFAAkJmxpaFgAQAgAFAAkJmxpaFgAQAgAAAA==.Mommystrasza:BAAALgAECgQJCQAAAA==.Monkfall:BAAALgADCgMJAwABLgAECgkJHgAeABkbAA==.Monkoreo:BAAALgADCgQJBAAAAA==.Monkwrld:BAABLgAECn8dAAIGAAgJZB12EAB5AgAGAAgJZB12EAB5AgAAAA==.Monty:BAAALgAECgYJCgAAAA==.Moosemode:BAAALgADCgcJBwAAAA==.Mordet:BAAALgAECgEJAQABLgAECggJFQAIAAAAAQ==.Moridane:BAAALgAECgEJBAABLgAECggJFQAIAAAAAQ==.',
Mu='Muffinz:BAABLgAECn8eAAIaAAgJUBC0HABOAQAaAAgJUBC0HABOAQAAAA==.',
My='Myau:BAABLgAECn8fAAIlAAgJDxaDDgDjAQAlAAgJDxaDDgDjAQAAAA==.Myera:BAAALgADCgUJBQAAAA==.Mynia:BAABLgAECn8oAAIBAAgJihGFDQDNAQABAAgJihGFDQDNAQAAAA==.Mythrius:BAAALgAECgUJCwAAAA==.',
['Mø']='Mørdu:BAAALgAECgUJCQAAAA==.',
Na='Nada:BAAALgAECgUJCQAAAA==.Nano:BAABLgAECn8hAAIKAAgJ9RiYGAAeAgAKAAgJ9RiYGAAeAgAAAA==.Nardor:BAAALgAECgYJDgAAAA==.Naturelle:BAABLgAECn8WAAMEAAYJPQW+XgCjAAAEAAYJPQW+XgCjAAADAAIJFwFBigAlAAAAAA==.Nautilius:BAAALgADCggJDwAAAA==.Navaani:BAABLgAECn8lAAIjAAgJdR++AwBdAgAjAAgJdR++AwBdAgAAAA==.Nazdreg:BAACLgAFFH8GAAIKAAMJAQwOOgCfAAAKAAMJAQwOOgCfAAAuAAQKfx0AAwoABwmNHYwzAD4CAAoABwmNHYwzAD4CAAsAAQkAAHmBAAYAAAAA.Nazgull:BAAALgAECgIJAgAAAA==.',
Ne='Neisa:BAAALgADCgMJAwAAAA==.Nemesicc:BAAALgAECgUJDQAAAA==.Neotoldir:BAABLgAECn8mAAMeAAgJ+h3pBgAmAgAeAAcJOyDpBgAmAgAnAAgJLRcXBAC2AQAAAA==.Nerfdisc:BAAALgAECgYJCgAAAA==.Nerfdruids:BAAALgADCgUJBQAAAA==.Nerozond:BAAALgAECgEJAgAAAA==.Netalli:BAABLgAECn8UAAIcAAgJmyB1JwDUAgAcAAgJmyB1JwDUAgABLgAFFAQJCgAHALgeAA==.Nevershocked:BAABLgAECn8WAAITAAgJHhT9GgBmAQATAAgJHhT9GgBmAQAAAA==.Nezziee:BAAALgAECgkJEwAAAA==.',
Ni='Nibroc:BAAALgAECgYJCgAAAA==.Nidhoggy:BAABLgAECn8VAAMMAAYJZBvkMwC0AQAMAAYJZBvkMwC0AQAYAAIJ0AUTgQBDAAAAAA==.Nife:BAAALgAECgEJAQAAAA==.',
No='Nordie:BAAALgAECgcJEwAAAA==.Noriss:BAAALgAECgEJAQABLgAECggJFQAIAAAAAQ==.Northik:BAABLgAECn8mAAMHAAgJYSBWHwDFAgAHAAgJYSBWHwDFAgAeAAYJ7Q1zGgDzAAAAAA==.Notintheface:BAAALgAECgYJEAAAAA==.',
Nu='Numlock:BAAALgAECgcJEAAAAA==.',
Ny='Nydav:BAABLgAECn8kAAIGAAgJAyMvBACqAgAGAAgJAyMvBACqAgAAAA==.Nyphithys:BAAALgAECgUJBQAAAA==.Nystallina:BAAALgADCgMJAwAAAA==.',
['Ní']='Níítefall:BAABLgAECn8iAAMUAAkJYx91AwCbAgAUAAgJaR91AwCbAgAOAAYJGhKPRQAoAQABLgAECggJHQAcAOsiAA==.',
Oa='Oakbreaker:BAAALgAECgMJAwABLgAFFAMJBwAiAKIdAA==.',
Ob='Obalma:BAAALgAECgYJDQAAAA==.',
Oc='Ocyria:BAAALgADCgEJAQAAAA==.',
Od='Odrade:BAAALgADCgIJAgAAAA==.Odwalla:BAACLgAFFH8RAAMQAAUJHh/jCwBqAQAQAAUJHh/jCwBqAQABAAIJoBeuEwC1AAAuAAQKfyMABBAACAlQIwoKAPgCABAACAlQIwoKAPgCAAEABgmtHykVAHUBAAIAAwkMFExkAK8AAAAA.',
Oh='Ohgodno:BAAALgAECgcJEgAAAA==.',
Ok='Oktal:BAAALgAECgYJBgAAAA==.',
Ol='Olmec:BAABLgAECn8lAAIYAAgJDhMZFQCrAQAYAAgJDhMZFQCrAQAAAA==.',
On='Onlydesert:BAAALgAECgYJDAAAAA==.',
Oo='Ookla:BAAALgADCggJCAAAAA==.Oorudun:BAAALgADCgYJBgAAAA==.',
Op='Ophiel:BAAALgAECgUJCQAAAA==.Optiks:BAABLgAECn8YAAIcAAgJXhdCLQDsAQAcAAgJXhdCLQDsAQAAAA==.',
Or='Orblio:BAAALgADCgQJBAAAAA==.Orcofhell:BAAALgAECgMJBAAAAA==.Orcthas:BAAALgAECgUJCgAAAA==.Orksauce:BAACLgAFFH8HAAIiAAMJoh3CDwAqAQAiAAMJoh3CDwAqAQAuAAQKfykAAyIACAkEJbMBAPcCACIACAkEJbMBAPcCACEAAQnZFgocAEgAAAAA.Orleron:BAAALgADCgkJDAAAAA==.Oroth:BAAALgAECgYJDwAAAA==.',
Os='Osares:BAAALgAECgYJDgAAAA==.Oshizitskoro:BAAALgAECgIJAgAAAA==.',
Ot='Otsu:BAAALgADCgMJAwABLgAECgYJDgAIAAAAAA==.',
Ou='Outofwater:BAAALgADCgYJBgAAAA==.Outtyfox:BAAALgADCgIJAgAAAA==.',
Ow='Owlkin:BAAALgAECgUJBQABLgAECgkJMQAFAI8cAA==.',
['Oß']='Oß:BAAALgAECgcJDwABLgAECggJLQAGALoQAA==.',
Pa='Pagophobia:BAAALgADCgEJAQAAAA==.Pakku:BAABLgAECn8dAAIcAAgJZxrfIAAmAgAcAAgJZxrfIAAmAgAAAA==.Palilicious:BAAALgAECgUJBgAAAA==.Pallytree:BAAALgAECgcJCQAAAA==.Pantheeon:BAAALgADCggJCwAAAA==.Paradom:BAAALgADCgIJAgAAAA==.Parzival:BAABLgAECn8bAAIcAAcJLgteYgBNAQAcAAcJLgteYgBNAQAAAA==.Patchface:BAAALgADCgcJBwAAAA==.',
Pd='Pdp:BAABLgAECn8VAAIDAAcJiCO0FgBXAgADAAcJiCO0FgBXAgAAAA==.',
Pe='Perkbane:BAABLgAECn8WAAQJAAgJBBxeEAAoAQAJAAUJJB9eEAAoAQAKAAcJuBOmmwAiAQALAAIJnQ/STgCBAAAAAA==.Perkdragon:BAAALgAECgYJBQABLgAECggJFgAJAAQcAA==.Perkyl:BAAALgAECgYJEgAAAA==.Petrol:BAAALgAECgYJBwAAAA==.',
Ph='Phage:BAAALgAECgEJAgABLgAECgcJFgASAPIdAA==.Pheel:BAAALgAECgUJBQAAAA==.Phillactery:BAAALgAECgMJAwAAAA==.Phlykz:BAAALgAECgMJAwAAAA==.Phosho:BAAALgADCgYJBgAAAA==.',
Pi='Pig:BAAALgAECgQJBAAAAA==.Pikevarr:BAAALgAECgcJEAAAAA==.',
Pk='Pkrage:BAABLgAECn8mAAMgAAkJfxjmCwBOAgAgAAkJfxjmCwBOAgAXAAEJTAA7twAIAAAAAA==.',
Pl='Plagueborne:BAAALgAECggJDgAAAA==.Plazzy:BAABLgAECn8uAAQiAAkJiRy4BgBDAgAiAAkJiRy4BgBDAgAhAAYJYBc+BwBvAQAoAAEJMw8wEgA7AAAAAA==.Plopp:BAEALgAECgcJEwAAAA==.',
Po='Pollywog:BAAALgADCgYJBgABLgAFFAUJFgAFAA4lAA==.Polyethylene:BAABLgAECn8XAAIMAAcJUAauQAAAAQAMAAcJUAauQAAAAQAAAA==.Popprocks:BAAALgADCgEJAQAAAA==.Poxx:BAAALgAECgEJAgAAAA==.',
Pr='Praxis:BAAALgADCgcJAQABLgAECggJHwAKAL8XAA==.Pretzel:BAAALgAECgEJBQABLgAECggJFQAIAAAAAQ==.Proxymate:BAAALgADCgMJAwAAAA==.',
Pu='Puhtty:BAAALgAECgMJAwAAAA==.Punkfangs:BAAALgADCgcJFAAAAA==.',
['Pë']='Pëaches:BAAALgADCgcJBwABLgAFFAUJEQAOABELAA==.',
['Pï']='Pï:BAAALgAECgQJBgAAAA==.',
Qk='Qkoira:BAAALgADCgYJBgABLgADCgcJCgAIAAAAAA==.',
Qu='Quanlain:BAABLgAECn8XAAMQAAgJQBkTHgDoAQAQAAgJQBkTHgDoAQACAAMJmBWHZgClAAAAAA==.Quasár:BAAALgAECgcJDQAAAA==.Quilara:BAAALgADCgkJHQAAAA==.Quillathe:BAABLgAECn8dAAMNAAgJvRP9CwARAgANAAgJvRP9CwARAgAlAAEJbQYoZQAuAAAAAA==.',
Ra='Radíant:BAAALgADCgUJBQABLgABCgYJBgAIAAAAAA==.Ragemaster:BAAALgAECgQJCQAAAA==.Ramiusraven:BAAALgADCgIJAgAAAA==.Rancore:BAABLgAECn8iAAMXAAgJ9RZ6FADIAQAXAAgJ9RZ6FADIAQAZAAMJcgqgKwCXAAAAAA==.Rashdar:BAACLgAFFH8KAAIPAAQJzwU4JAAbAQAPAAQJzwU4JAAbAQAuAAQKfxcAAg8ACAmHFotDABoCAA8ACAmHFotDABoCAAAA.Rattpack:BAABLgAECn8XAAMOAAcJng6fYADeAAAVAAUJ4xLyOAAfAQAOAAUJXAqfYADeAAAAAA==.Raves:BAABLgAECn8cAAIcAAYJUiDeVwAxAgAcAAYJUiDeVwAxAgAAAA==.',
Re='Regilz:BAAALgAECgYJDQAAAA==.Repent:BAAALgAECgkJBwAAAA==.Reselience:BAAALgAECgQJBAABLgAFFAUJBQAKAM8DAA==.Rewara:BAAALgADCgcJBwAAAA==.',
Rh='Rhadamenth:BAAALgADCgMJAwAAAA==.Rhinity:BAAALgADCgQJBAABLgAECgYJEwAIAAAAAA==.Rhyolite:BAAALgAECgEJAQAAAA==.',
Ri='Riaeviana:BAABLgAECn8VAAIOAAcJvBo2NgBdAQAOAAcJvBo2NgBdAQAAAA==.Ribeyye:BAAALgAECgcJCQAAAA==.Rigormistis:BAAALgADCgEJAQAAAA==.Rilde:BAAALgADCgcJBwAAAA==.Rinjielune:BAAALgADCgYJDwAAAA==.Risch:BAAALgAECgMJAwAAAA==.Rius:BAAALgADCgIJAgAAAA==.',
Ro='Roberts:BAAALgADCgkJEAAAAA==.Robroy:BAAALgAECgkJAQAAAA==.Robroÿ:BAAALgAECgYJEgAAAA==.Robrõy:BAAALgAECgkJBgABLgAECgkJCgAIAAAAAA==.Roku:BAAALgAFFAIJAgABLgAFFAYJIAAKALAgAA==.Romex:BAAALgADCgEJAQAAAA==.Rondo:BAAALgADCgUJBQAAAA==.Roseclaw:BAEALgAECgYJCwAAAA==.Roseclawed:BAEALgAECgYJCwABLgAECgYJCwAIAAAAAA==.Roxcee:BAAALgADCgkJCQABLgAECggJFgAkALUYAA==.Roxso:BAACLgAFFH8bAAIcAAcJDB2+AgBOAgAcAAcJDB2+AgBOAgAuAAQKfyAAAhwACQkQJaICANQDABwACQkQJaICANQDAAAA.',
Ru='Runnigan:BAAALgADCgQJBAAAAA==.',
Rx='Rxse:BAAALgAECgYJEAAAAA==.',
Ry='Rylun:BAAALgADCgYJCQAAAA==.',
['Rà']='Rànik:BAAALgADCgIJAgAAAA==.',
['Rë']='Rëdmagma:BAABLgAECn8YAAIYAAgJ8xRvGACNAQAYAAgJ8xRvGACNAQAAAA==.',
['Rö']='Röbin:BAAALgAECgEJAQAAAA==.',
Sa='Saasaki:BAAALgAECgYJDgAAAA==.Sabrinacarp:BAABLgAECn8kAAIkAAgJuxm1EwD2AQAkAAgJuxm1EwD2AQAAAA==.Sabryelle:BAAALgADCgEJAgAAAA==.Sacrelicious:BAABLgAECn8bAAIPAAcJPQ/pUgBOAQAPAAcJPQ/pUgBOAQAAAA==.Sagewynn:BAAALgAECgYJCgAAAA==.Salfroc:BAABLgAECn8pAAMJAAgJgBnCAgDwAQAJAAgJgBnCAgDwAQALAAIJ5QrmJQA8AAAAAA==.Saltychief:BAAALgADCgUJBwAAAA==.Saplo:BAABLgAECn8iAAIQAAgJPAvqNAB5AQAQAAgJPAvqNAB5AQAAAA==.Sapphiraflux:BAAALgADCgIJAgAAAA==.Sarif:BAAALgADCgcJDAAAAA==.Sarvashi:BAAALgAECgMJBAAAAA==.Sasara:BAAALgAECgMJBgAAAA==.Sathas:BAAALgADCgQJBAAAAA==.Saxel:BAAALgAECggJEAAAAA==.',
Sc='Scrabble:BAAALgAECgMJBAAAAA==.',
Se='Segio:BAAALgAECggJEAAAAA==.Selcia:BAABLgAECn8UAAIcAAcJYRgVQwCeAQAcAAcJYRgVQwCeAQAAAA==.Serenati:BAABLgAECn8UAAIPAAgJ3RMGOACfAQAPAAgJ3RMGOACfAQAAAA==.Sermour:BAAALgAECgEJAQAAAA==.',
Sh='Shadephoenix:BAABLgAECn8fAAInAAgJSwVDCQAJAQAnAAgJSwVDCQAJAQAAAA==.Shados:BAAALgAFFAEJAQAAAA==.Shadowen:BAAALgAECgYJCgAAAA==.Shambülance:BAAALgADCgEJAQAAAA==.Sharavia:BAABLgAECn8fAAIVAAgJEAw+EgBmAQAVAAgJEAw+EgBmAQAAAA==.Shari:BAABLgAECn8ZAAILAAcJdhIfCABcAQALAAcJdhIfCABcAQAAAA==.Shatoo:BAAALgAECgYJDwAAAA==.Shaunchaos:BAAALgADCgMJAwAAAA==.Shaunrawr:BAABLgAECn8hAAMQAAgJ6Bh3JADDAQAQAAgJ6Bh3JADDAQACAAIJ5wX0ewBUAAAAAA==.Shield:BAAALgAECgUJBQAAAA==.Shiftedtea:BAAALgAECgEJAQAAAA==.Shizaxe:BAAALgAECgIJAwAAAA==.Shizish:BAABLgAECn8UAAQGAAgJthr9DQDYAQAGAAYJ9hn9DQDYAQAFAAUJ0BVRMwAmAQAaAAUJ0AhQXADSAAAAAA==.Shocktuah:BAABLgAECn8iAAIYAAcJHCRNCgA1AgAYAAcJHCRNCgA1AgAAAA==.Shonúff:BAABLgAECn8qAAMGAAgJyRtQDAD0AQAGAAcJLB1QDAD0AQAFAAcJ4xKXGgB3AQAAAA==.Shotaro:BAABLgAECn8VAAMkAAYJdyAWEAAeAgAkAAYJdyAWEAAeAgAjAAQJlhhQHQAfAQAAAA==.Shox:BAAALgAECgEJAQAAAA==.',
Si='Sillybear:BAAALgAECgQJBQAAAA==.Silvermain:BAAALgADCgQJBAAAAA==.Sinful:BAABLgAECn8nAAMQAAgJMROGLgD3AQAQAAgJMROGLgD3AQACAAMJ6AA7fwBJAAAAAA==.Singarti:BAAALgAECggJDgAAAA==.Sizzlesnout:BAAALgAECgMJAwAAAA==.',
Sk='Skalagrim:BAAALgADCgMJAwAAAA==.Skedu:BAAALgADCgEJAQAAAA==.Skeptyk:BAABLgAECn8YAAIRAAcJiR02CgBEAgARAAcJiR02CgBEAgAAAA==.Skolivia:BAECLgAFFH8KAAMlAAQJGwnkDQAvAQAlAAQJGwnkDQAvAQANAAEJ9AGqKgA4AAAuAAQKfxYAAyUACAn6GGAZABYCACUACAn6GGAZABYCAA0AAglfEJhJAHEAAAAA.Skroggo:BAAALgAECgQJBgAAAA==.Skådoosh:BAABLgAECn8tAAMGAAgJuhCmFwBpAQAGAAgJuhCmFwBpAQAaAAcJ+wfoKQD7AAAAAA==.',
Sl='Slightdawn:BAAALgADCgkJCQAAAA==.Sloppymop:BAAALgADCgUJCAAAAA==.Sloppysteaks:BAAALgADCgUJBQAAAA==.',
Sm='Smallben:BAAALgADCgIJAgAAAA==.Smiley:BAAALgAECgYJDgAAAA==.Smite:BAAALgADCgIJAgAAAA==.Smitti:BAAALgAECgMJAwAAAA==.Smug:BAABLgAECn8mAAIOAAkJ6iTFAQBDAwAOAAkJ6iTFAQBDAwAAAA==.',
Sn='Snapcrklepop:BAAALgADCgUJBQAAAA==.Sniffledoo:BAABLgAECn8YAAIgAAgJ2RE7DQCPAQAgAAgJ2RE7DQCPAQAAAA==.Snuwuf:BAAALgADCgEJAQAAAA==.Snóóf:BAAALgAECgUJDQAAAA==.',
So='Solomeani:BAAALgAECgMJBAAAAA==.Sonicnoah:BAAALgAECgQJBAAAAA==.Sorokai:BAAALgADCggJCAAAAA==.Sourfangs:BAACLgAFFH8KAAIXAAQJRSB6BgBvAQAXAAQJRSB6BgBvAQAuAAQKfxcAAhcACAkmJZ4FAE0DABcACAkmJZ4FAE0DAAAA.Soxx:BAAALgAECgEJAQAAAA==.',
Sp='Sparklymayhm:BAAALgADCgkJFAAAAA==.Spearz:BAAALgADCgQJBAAAAA==.Speedmonster:BAAALgADCggJCAAAAA==.Spicymilk:BAABLgAECn8iAAIbAAgJoCH0AQCTAgAbAAgJoCH0AQCTAgAAAA==.Spicypeño:BAABLgAECn8jAAMTAAgJdh7ODQDwAQASAAYJPiE8DAAXAgATAAcJ/RvODQDwAQABLgAFFAgJGAATAKMSAA==.Spinach:BAABLgAECn8YAAMkAAcJWxJZKgA8AQAkAAYJ0BJZKgA8AQAPAAEJiwN/IQEbAAAAAA==.Spire:BAABLgAECn8eAAQcAAcJmgUgggANAQAcAAcJmgUgggANAQAbAAIJ8wELDABIAAAWAAEJPwFBEgAVAAAAAA==.Splithoofe:BAAALgAECgUJBQABLgAFFAIJCAAQAAsIAA==.Sprawl:BAABLgAECn81AAIoAAgJwxkLAgAqAgAoAAgJwxkLAgAqAgAAAA==.',
Sq='Squrrlydan:BAABLgAECn8VAAMgAAgJASDkBwAAAgAgAAcJ9B7kBwAAAgAXAAYJXhvLSACBAQAAAA==.',
St='Stains:BAAALgADCgYJBgABLgAECgcJFgASAPIdAA==.Staint:BAABLgAECn8WAAISAAcJ8h09DQAFAgASAAcJ8R09DQAFAgAAAA==.Starnights:BAABLgAECn8UAAInAAgJCAv1BgBFAQAnAAgJCAv1BgBFAQAAAA==.Statman:BAABLgAECn8iAAIgAAgJaQ5XEQBOAQAgAAgJaQ5XEQBOAQAAAA==.Steelbubble:BAAALgAECgYJDwAAAA==.Stengah:BAABLgAECn8lAAImAAgJtyQCAQBQAwAmAAgJtyQCAQBQAwAAAA==.Steris:BAAALgADCgYJBgAAAA==.Strela:BAAALgAECggJKgAAAQ==.Stressummon:BAAALgADCgMJAgAAAA==.Strykie:BAAALgADCgQJBAAAAA==.Sturmgewehr:BAAALgADCggJCAAAAA==.',
Su='Sulina:BAAALgAECgYJDQAAAA==.Suzaki:BAAALgADCgkJCQAAAA==.',
Sv='Svetlian:BAAALgAECgUJCAABLgAECggJKgAIAAAAAA==.',
Sw='Swtblsphmy:BAABLgAECn8mAAMMAAgJeRK3LQDTAQAMAAgJeRK3LQDTAQAYAAIJZQQBbAAqAAAAAA==.',
Sy='Symphony:BAAALgADCgEJAQAAAA==.Syradora:BAAALgAECgYJEQAAAA==.Syynner:BAAALgAECgcJBwAAAA==.',
['Sä']='Säber:BAAALgAECgMJAwAAAA==.',
['Sè']='Sèd:BAAALgAECgUJBgAAAA==.Sèitheach:BAAALgAECgMJAwAAAA==.',
Ta='Taelak:BAAALgAECgcJEAAAAA==.Tahrin:BAABLgAECn8hAAIQAAgJ/RxVFgCFAgAQAAgJ/RxVFgCFAgAAAA==.Talamon:BAABLgAECn8iAAIaAAgJKxZLDgDjAQAaAAgJKxZLDgDjAQAAAA==.Talmøre:BAAALgADCgMJAwAAAA==.Talyyon:BAABLgAECn8WAAIKAAYJ+wG0nACEAAAKAAYJ+wG0nACEAAAAAA==.Tandinise:BAAALgAFFAIJBAAAAA==.Tandruid:BAAALgAECgMJBgABLgAFFAUJBQAKAM8DAA==.Tankmeta:BAAALgADCgMJAwAAAA==.Tanmonk:BAAALgAECgQJBAABLgAFFAUJBQAKAM8DAA==.Taproot:BAAALgAECgkJCQAAAA==.Tas:BAAALgADCgUJBgAAAA==.Tashi:BAABLgAECn8fAAICAAgJsxOaBgCsAQACAAgJsxOaBgCsAQAAAA==.Tasina:BAAALgAECgEJAQABLgAECgUJCAAIAAAAAA==.Tastictank:BAAALgAECgQJBgAAAA==.Taurenamos:BAABLgAECn8oAAQEAAgJXxTVGgDtAQAEAAgJXxTVGgDtAQADAAYJjhjfGgBfAQAfAAYJ5AaZGwB9AAAAAA==.Taynam:BAAALgAECgYJBwABLgAECgcJFAAHAEMhAA==.',
Te='Tebas:BAAALgAECgQJBQAAAA==.Teival:BAABLgAECn8fAAIQAAgJGhseFgAeAgAQAAgJGhseFgAeAgAAAA==.Tempëst:BAAALgADCgIJAgAAAA==.Tenchu:BAABLgAECn8PAAMVAAUJRBxgHgDlAAAVAAUJRBxgHgDlAAAOAAUJlA6JagDHAAAAAA==.Tenfour:BAAALgADCgYJBgAAAA==.Tenseven:BAAALgAECgYJDwAAAA==.Teredorn:BAAALgADCgkJCgABLgAECgkJHQAkAMwbAA==.Terrorbláde:BAAALgADCgcJBwAAAA==.Terrørßlade:BAAALgADCgYJBgAAAA==.',
Th='Thalinin:BAAALgADCgYJCAAAAA==.Thalion:BAAALgAECggJCQAAAA==.Thark:BAAALgAECgUJBgABLgAECggJHQAVAJokAA==.Theharmacist:BAAALgAECgQJBAAAAA==.Therris:BAABLgAECn8hAAIQAAgJMBANKQCtAQAQAAgJMBANKQCtAQAAAA==.Thideaes:BAAALgADCgYJBQAAAA==.Thidias:BAAALgAECgIJAgAAAA==.Thorimane:BAAALgAECgQJBAABLgAECggJFQAIAAAAAA==.Thrizzowd:BAAALgADCgkJDQAAAA==.Throwd:BAABLgAECn8pAAIiAAgJWRTZDADTAQAiAAgJWRTZDADTAQAAAA==.Thwark:BAAALgADCgQJBAABLgAECggJHQAVAJokAA==.',
Ti='Tinytony:BAABLgAECn8iAAMjAAkJrBNsDAB1AQAjAAcJ+BdsDAB1AQAPAAcJRQpfawAWAQAAAA==.',
To='Toranis:BAAALgAECgEJAQAAAA==.Torrellan:BAAALgADCgMJAwAAAA==.Torrents:BAABLgAECn8qAAQMAAgJpCMDAwAlAwAMAAgJpCMDAwAlAwAYAAUJaRItQACpAAApAAIJAQczJwBnAAAAAA==.Touchofchaos:BAAALgAECgEJAQAAAA==.Toxíc:BAAALgADCgcJEgAAAA==.',
Tr='Traffyfu:BAAALgAECgMJAwAAAA==.Trailerpark:BAAALgAECgkJAQAAAA==.Traver:BAAALgAECgQJBAAAAA==.Trinytee:BAAALgAECgMJBAAAAA==.Trogdor:BAAALgADCgQJBAAAAA==.',
Tu='Turbocarried:BAAALgAECgQJBgAAAA==.Ture:BAAALgADCgkJGQAAAA==.Turnandburn:BAAALgAECgIJBAAAAA==.',
Tw='Twistedsugar:BAAALgAECgMJAwAAAA==.Twìztid:BAABLgAECn8dAAIOAAgJniNxCQCPAgAOAAgJniNxCQCPAgAAAA==.',
Ty='Tyriäel:BAABLgAECn8pAAIeAAkJDx/VAgC5AgAeAAkJDx/VAgC5AgAAAA==.Tyrrible:BAAALgADCggJDwAAAA==.',
['Tà']='Tàyla:BAAALgADCgYJBgABLgAECgMJBAAIAAAAAA==.',
['Tð']='Tðxîc:BAAALgAECgEJAgAAAA==.',
Ul='Ulther:BAAALgAECgcJEAAAAA==.Ultìmecia:BAAALgAECgYJAQAAAA==.',
Un='Unbinddeath:BAAALgADCgQJBwAAAA==.Unfriendly:BAAALgADCgEJAQAAAA==.',
Up='Upside:BAAALgAECgYJDgAAAA==.',
Ur='Uruz:BAABLgAECn8cAAIXAAkJ9R5SGQCBAgAXAAkJ9R5SGQCBAgAAAA==.',
Ut='Uthêr:BAAALgADCgMJAwAAAA==.',
Va='Vacare:BAAALgAECgcJEAAAAA==.Valdyria:BAAALgADCgQJBwAAAA==.Valefar:BAAALgAECgYJDgAAAA==.Valkoienne:BAAALgAECgEJAQAAAA==.Valyniss:BAAALgAECgEJAgAAAA==.Vamp:BAAALgADCgUJBQAAAA==.Vanart:BAAALgAECgkJBQAAAA==.Vandemar:BAAALgAECgMJAwAAAA==.Vanderpump:BAAALgADCgYJBgABLgAECgkJKwANAKASAA==.Vanreu:BAAALgAECgYJBwAAAA==.Vavictus:BAAALgAECgcJEAAAAA==.',
Ve='Vedronorael:BAAALgADCgkJFgAAAA==.Vekkar:BAAALgAECgEJAQAAAA==.Velanthia:BAAALgAECgEJAQAAAA==.Vengrath:BAABLgAECn8YAAIcAAgJPiJXEgCGAgAcAAgJPiJXEgCGAgAAAA==.Venomgodd:BAAALgADCgEJAQAAAA==.Verderben:BAAALgAECgYJCgAAAA==.',
Vi='Vibestotem:BAAALgAECgEJAQAAAA==.Vilenia:BAAALgAECgcJEwAAAA==.Vilkasdk:BAAALgAECgYJCQAAAA==.Vinchenzo:BAAALgAECgIJAgAAAA==.Vinhelsin:BAAALgAECgQJBAAAAA==.Violetangel:BAAALgAECgYJBQAAAA==.Vionir:BAABLgAECn8iAAIBAAgJjiNYBgBLAgABAAgJjiNYBgBLAgAAAA==.Vitality:BAAALgAECgIJAgAAAA==.',
Vo='Voidrush:BAAALgAECgcJEAAAAA==.Voirdire:BAABLgAECn8UAAIPAAgJsAa8XQA0AQAPAAgJsAa8XQA0AQAAAA==.Voron:BAAALgAECgcJDQAAAA==.',
Vu='Vulpa:BAABLgAECn8mAAMLAAgJCQ9SCQBDAQALAAgJCQ9SCQBDAQAKAAIJFAKHDwE/AAAAAA==.',
Vy='Vynessa:BAAALgADCgkJFAAAAA==.Vyshareth:BAAALgADCgcJBwAAAA==.',
Wa='Wanren:BAAALgAECgQJBAAAAA==.Wargodd:BAAALgADCgMJAwAAAA==.Waterwhip:BAABLgAFFH8FAAIMAAIJSwo/HACFAAAMAAIJSwo/HACFAAAAAA==.',
We='Westfall:BAABLgAECn8eAAMeAAkJGRsZDQA+AgAeAAkJChsZDQA+AgAHAAcJ7gxLTgBRAQAAAA==.',
Wh='Whirl:BAABLgAECn8VAAIHAAgJqRTsKgDQAQAHAAgJqRTsKgDQAQAAAA==.Whirlock:BAAALgADCgYJBgAAAA==.Whirlwind:BAABLgAECn8dAAIXAAcJaBpBKgAQAgAXAAcJaBpBKgAQAgABLgAECggJFQAHAKkUAA==.Whydoiexist:BAABLgAECn8VAAIaAAYJHCAGHQAbAgAaAAYJHCAGHQAbAgABLgAECggJHgAmALMkAA==.',
Wi='Willrun:BAABLgAECn8WAAMDAAYJqQa9MwDAAAADAAYJqQa9MwDAAAAdAAEJYgQVNwAqAAAAAA==.Windwatcher:BAABLgAECn8kAAIYAAcJngvNJgAkAQAYAAcJngvNJgAkAQAAAA==.Witheredyam:BAAALgAECgEJAQAAAA==.Withirony:BAAALgAECgYJBwAAAA==.',
Wo='Wompeal:BAABLgAECn8fAAIRAAgJXR60CADAAgARAAgJXR60CADAAgAAAA==.Wonkwonk:BAABLgAECn8YAAIcAAgJIQQ6gQAPAQAcAAgJIQQ6gQAPAQAAAA==.Worth:BAABLgAECn8iAAIPAAgJhiGFCQC+AgAPAAgJhiGFCQC+AgAAAA==.',
Wr='Wrathofdirt:BAAALgADCgUJBQAAAA==.Wravin:BAABLgAECn8nAAIQAAkJ1g7xKACuAQAQAAkJ1g7xKACuAQABLgAECgkJJwARAJsNAA==.Wrukolas:BAABLgAECn8YAAIKAAcJewmfUAA4AQAKAAcJewmfUAA4AQAAAA==.',
Wu='Wulf:BAAALgAECgEJAQAAAA==.Wumdaorm:BAAALgADCgEJAQAAAA==.',
Wy='Wyhm:BAAALgADCgUJBwAAAA==.Wystan:BAABLgAECn8qAAIMAAgJ2BppDgBRAgAMAAgJ2BppDgBRAgAAAA==.',
['Wé']='Wés:BAABLgAECn8iAAIaAAgJ1BkACwASAgAaAAgJ1BkACwASAgAAAA==.',
['Wí']='Wíckedwítch:BAAALgAECgcJDQAAAA==.',
Xa='Xalatoes:BAAALgADCgEJAwAAAA==.Xanden:BAAALgADCgcJCAAAAA==.Xanthe:BAABLgAECn8gAAMkAAgJUAftKABGAQAkAAgJUAftKABGAQAPAAEJIwQVWAEnAAAAAA==.Xayden:BAAALgADCgMJAwAAAA==.',
Xe='Xeal:BAAALgAECgYJEQAAAA==.Xelkath:BAAALgAECgcJEwAAAA==.Xenomorphic:BAACLgAFFH8RAAIFAAUJXRxSBwCxAQAFAAUJXRxSBwCxAQAuAAQKfyEAAgUACQkSIskBAFgDAAUACQkSIskBAFgDAAAA.Xentow:BAABLgAECn8hAAIQAAgJjAkIOgBlAQAQAAgJjAkIOgBlAQAAAA==.',
Xu='Xuanfeng:BAAALgAECgYJEQAAAA==.',
Xy='Xythros:BAAALgADCggJCAAAAA==.',
Ya='Yacob:BAAALgADCgEJAgABLgAECggJHAARAGMcAA==.Yamling:BAAALgAECgEJAQAAAA==.Yarel:BAACLgAFFH8JAAIFAAUJxwdSBgBjAQAFAAUJxwdSBgBjAQAuAAQKfyoAAwUACQmdHtsNAHgCAAUACQmdHtsNAHgCAAYACQldGSgQALsBAAEuAAUUAgkCAAgAAAAA.Yayaka:BAAALgAFFAEJAwAAAA==.',
Yi='Yizdano:BAACLgAFFH8HAAIiAAMJiyLMDwAqAQAiAAMJiyLMDwAqAQAuAAQKfyYAAyIACAl5ITkDAKoCACIACAl5ITkDAKoCACEAAQlrFG0dAEAAAAAA.',
Yo='Yoloscrap:BAAALgADCgYJBQAAAA==.',
Yu='Yukiina:BAAALgAECgMJAwAAAA==.',
['Yù']='Yùm:BAAALgAECgcJDAABLgAECgkJJwAcAJUcAA==.',
Za='Zaccheus:BAABLgAECn8UAAMFAAYJVBG9IAA/AQAFAAYJVBG9IAA/AQAGAAYJTwZ/SgDpAAAAAA==.Zalruin:BAAALgADCgkJCgAAAA==.Zambora:BAAALgAECgcJBwAAAA==.Zarb:BAAALgADCggJCAAAAA==.',
Ze='Zeebra:BAABLgAECn8VAAMbAAYJag0kBQAoAQAbAAYJag0kBQAoAQAcAAUJQwa0pQDIAAAAAA==.Zeenii:BAAALgADCgMJAwAAAA==.Zeesaw:BAABLgAECn8dAAMXAAcJbx2tFwCpAQAXAAcJcBytFwCpAQAZAAYJwhGDEwAhAQAAAA==.Zeretrix:BAABLgAECn8nAAIcAAkJzxxTEACXAgAcAAkJzxxTEACXAgAAAA==.Zeroperfect:BAAALgADCgUJBQAAAA==.',
Zi='Zikà:BAAALgADCgMJAwAAAA==.Zinni:BAAALgADCgIJAgAAAA==.Ziros:BAAALgAECgYJBQAAAA==.',
Zl='Zlutar:BAAALgAECgMJBQAAAA==.',
Zo='Zonotix:BAAALgAECgMJAwAAAA==.',
Zy='Zynos:BAABLgAECn8eAAIOAAgJlg2PTQAQAQAOAAgJlg2PTQAQAQAAAA==.',
['Âl']='Âllatår:BAAALgADCgUJBQABLgAECgYJBgAIAAAAAA==.',
['Ãl']='Ãlexstrasza:BAAALgADCgUJAwAAAA==.',
['Ça']='Çalindrel:BAAALgADCgkJCQAAAA==.',
['Ñu']='Ñuk:BAAALgAECgUJCQAAAA==.',
['Úà']='Úà:BAAALgADCgcJCgAAAA==.',
['Üb']='Überhealz:BAAALgAECgMJAwABLgAECgYJFAAFAFQRAA==.',
['ßö']='ßöw:BAABLgAECn8gAAMQAAgJFRIEKACyAQAQAAgJFRIEKACyAQACAAYJZghuWQDfAAAAAA==.',
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
