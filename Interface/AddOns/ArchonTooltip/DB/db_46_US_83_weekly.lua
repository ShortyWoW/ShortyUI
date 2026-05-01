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

local lookup = {'Mage-Frost','Druid-Restoration','Warrior-Protection','Hunter-Marksmanship','Druid-Guardian','Monk-Windwalker','Shaman-Restoration','Shaman-Enhancement','DeathKnight-Unholy','Unknown-Unknown','Hunter-BeastMastery','Paladin-Holy','DemonHunter-Devourer','Priest-Holy','Rogue-Assassination','Rogue-Subtlety','Monk-Mistweaver','Paladin-Retribution','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Druid-Balance','Hunter-Survival','Priest-Shadow','Warrior-Arms','Warrior-Fury','Mage-Arcane','DemonHunter-Havoc','Shaman-Elemental','Warlock-Demonology','Druid-Feral','Rogue-Outlaw','DeathKnight-Frost','DeathKnight-Blood','Warlock-Affliction','Warlock-Destruction','Mage-Fire','Priest-Discipline','Paladin-Protection','DemonHunter-Vengeance','Monk-Brewmaster',}
local provider = {region='US',realm='EarthenRing',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abrothael:BAAALgAECgcJDAAAAA==.',
Ad='Adorèè:BAAALgAECgYJCwAAAA==.Adrestia:BAAALgAECggJCAAAAA==.',
Ae='Aelinqt:BAAALgAFFAEJAgAAAA==.Aestua:BAAALgADCgMJAwAAAA==.Aetheros:BAAALgADCgUJBQAAAA==.Aezer:BAAALgAECgEJAQAAAA==.',
Ah='Ahvb:BAACLgAFFH8IAAIBAAMJsBXbMgACAQABAAMJsBXbMgACAQAuAAQKfycAAgEABwmIIf8UADMCAAEABwmIIf8UADMCAAAA.',
Ai='Airlinna:BAABLgAECn8oAAICAAgJsRVdGQC1AQACAAgJsRVdGQC1AQAAAA==.Airoach:BAAALgAECgYJDQAAAA==.',
Ak='Akumaki:BAAALgAECgMJAgAAAA==.',
Al='Alaraen:BAABLgAECn8VAAIDAAYJ6hBVEgACAQADAAYJ6hBVEgACAQAAAA==.Alcremie:BAAALgAECgYJCAABLgAFFAcJDAAEADIWAA==.Aleve:BAAALgADCgcJDgAAAA==.Alilyanea:BAAALgADCgMJAwAAAA==.Alinera:BAAALgADCgYJEAAAAA==.Allaire:BAAALgAECgYJAgAAAA==.Almarii:BAAALgADCgQJBAAAAA==.Alraune:BAABLgAECn8eAAIFAAkJaRVgBgCWAQAFAAkJaRVgBgCWAQAAAA==.Alvara:BAABLgAECn8XAAIGAAcJXxy6CQDbAQAGAAcJXxy6CQDbAQAAAA==.Alynndra:BAAALgAECgQJCAAAAA==.Alyssazoe:BAAALgADCgUJBQAAAA==.',
Am='Amai:BAACLgAFFH8GAAIHAAMJ3xJQFQDhAAAHAAMJ3xJQFQDhAAAuAAQKfzIAAwcACQnWIfMAAE4DAAcACQnWIfMAAE4DAAgAAQluAcwvACUAAAAA.Amapull:BAAALgAECgEJAQAAAA==.Amarrantha:BAABLgAECn8bAAIJAAcJVhcKKACdAQAJAAcJVhcKKACdAQAAAA==.Amorrel:BAAALgADCgUJBQABLgAECgUJDAAKAAAAAA==.',
An='Anarionhunts:BAABLgAECn8XAAILAAgJaBYiHgCrAQALAAgJaBYiHgCrAQAAAA==.Andius:BAAALgADCgkJHQAAAA==.Anirra:BAAALgAECgUJDAAAAA==.Anwylina:BAAALgADCgUJBQAAAA==.',
Ap='Apert:BAABLgAECn8ZAAIMAAcJBiakAgDsAgAMAAcJBiakAgDsAgAAAA==.Apnea:BAAALgADCgUJBQAAAA==.',
Ar='Arc:BAABLgAECn8ZAAINAAgJHhlwPAACAgANAAgJHhlwPAACAgAAAA==.Arcadien:BAAALgAECgQJBAAAAA==.Arcbringer:BAAALgAECgYJDgAAAA==.Ardulithil:BAAALgADCgIJAgABLgAECgYJBgAKAAAAAA==.Ari:BAAALgADCgcJBwAAAA==.Ariairi:BAAALgADCgkJIQABLgAECgUJDAAKAAAAAA==.Arklightess:BAAALgAECgYJBwAAAA==.Arroezze:BAAALgAECgYJDQAAAA==.Arsibalt:BAAALgADCgEJAQAAAA==.Arthurin:BAAALgADCgYJCQAAAA==.',
As='Ashayo:BAAALgADCgkJIwAAAA==.Asymmetry:BAABLgAECn8bAAIOAAcJpyVgAgDkAgAOAAcJpyVgAgDkAgAAAA==.',
At='Athelstan:BAAALgAECgYJDQAAAA==.Aticus:BAAALgADCgIJAgAAAA==.',
Au='Audaria:BAAALgADCgYJDgAAAA==.Audery:BAAALgAECgYJBgABLgAECggJEAAKAAAAAA==.Augkward:BAAALgADCgEJAQAAAA==.Aureldor:BAAALgAECgQJBAAAAA==.Automatic:BAABLgAECn8aAAMPAAgJpBXSBQAoAgAPAAgJXxXSBQAoAgAQAAMJIwvuLgBFAAAAAA==.',
Av='Avinia:BAAALgAECgUJCAAAAA==.Avorek:BAAALgAECgEJAQAAAA==.Avoric:BAAALgADCgYJCgAAAA==.Avorik:BAAALgAECgQJDgAAAA==.Aváss:BAAALgAECgEJAQAAAA==.',
Ay='Ayesia:BAAALgADCgYJCQAAAA==.',
Az='Azaree:BAAALgAECgYJBgABLgAECgYJDwAKAAAAAA==.Azatra:BAAALgADCgYJDAAAAA==.Azenetal:BAAALgAECgEJAQAAAA==.Azndak:BAAALgAECgIJAgAAAA==.Azriell:BAABLgAECn8TAAINAAcJ/x+HNgAdAgANAAcJ/x+HNgAdAgAAAA==.Aztec:BAAALgADCgEJAQAAAA==.',
Ba='Babababoon:BAABLgAECn8bAAIJAAgJnB+LHADcAQAJAAgJnB+LHADcAQAAAA==.Bael:BAAALgAECgYJCAAAAA==.Ballinacup:BAAALgADCgYJCgAAAA==.Baloo:BAABLgAECn8pAAICAAgJ3Bl1DgAmAgACAAgJ3Bl1DgAmAgAAAA==.Bandeto:BAAALgAECgYJBgAAAA==.Barboosa:BAAALgAECgEJAgAAAA==.Barcmaul:BAAALgAECgQJBAAAAA==.Bathzalts:BAAALgAECgEJAQAAAA==.Baylel:BAAALgAECgUJCQAAAA==.',
Bb='Bbqdh:BAAALgADCgYJBAABLgAECgYJEAAKAAAAAA==.',
Be='Beamz:BAAALgAECgQJBwAAAA==.Bearylikely:BAAALgAECgUJBgABLgAECggJGAARAGgMAA==.Belledolphin:BAAALgAECgQJBQAAAA==.Bellgold:BAAALgADCgMJCQABLgAECgcJGwASABQNAA==.Bells:BAAALgADCgQJBAAAAA==.Berigo:BAAALgAECgYJEQAAAA==.Berleos:BAAALgAECgcJDwAAAA==.Bertoxulous:BAAALgAECgYJAgAAAA==.Bezdk:BAAALgADCggJEAABLgAECggJHQATADQYAA==.Bezvoker:BAABLgAECn8dAAQTAAgJNBj5DgBJAgATAAgJNBj5DgBJAgAUAAQJOxPUCgC9AAAVAAMJ4RZdSgCrAAAAAA==.',
Bi='Bigpork:BAAALgADCgcJDQAAAA==.Bigzig:BAAALgAECgYJEAAAAA==.Billblur:BAAALgAECgEJAQAAAA==.',
Bj='Björn:BAAALgADCgcJBwAAAA==.',
Bl='Blackschwarz:BAAALgAECgMJBgAAAA==.Blasta:BAAALgADCgYJCQAAAA==.Bleunienn:BAAALgADCgYJDgAAAA==.Blrglr:BAAALgADCgYJCAAAAA==.Blueberrypie:BAABLgAECn8jAAIHAAgJrB5xCgBCAgAHAAgJrB5xCgBCAgAAAA==.',
Bo='Boerc:BAAALgAECgYJAgAAAA==.Bolvek:BAAALgADCgYJBgAAAA==.Bonnieblue:BAAALgAECgQJBwAAAA==.Borbory:BAABLgAECn8gAAIHAAgJWB6EBAC2AgAHAAgJWB6EBAC2AgAAAA==.',
Br='Brasca:BAABLgAECn8ZAAIUAAcJexpYAgD1AQAUAAcJexpYAgD1AQAAAA==.Breloom:BAAALgAECgEJAQAAAA==.Brighthammer:BAAALgADCgkJJgAAAA==.Brisketdk:BAAALgAECgYJEAAAAA==.Bruhmal:BAABLgAECn8ZAAMCAAgJcR6ZBgCsAgACAAgJcR6ZBgCsAgAWAAMJkhbkJgDOAAAAAA==.Brunner:BAAALgAECgYJCQAAAA==.Brynndolin:BAAALgAECgcJEwAAAA==.',
Bu='Bumble:BAEBLgAECn8iAAIXAAgJaSKCBADPAgAXAAgJaSKCBADPAgAAAA==.Burzolog:BAABLgAECn8gAAIQAAgJRBkABQA3AgAQAAgJRBkABQA3AgAAAA==.Buthis:BAAALgADCgUJBQAAAA==.Butsugen:BAAALgADCgMJAwAAAA==.',
Bv='Bvbs:BAAALgAECgYJEAAAAA==.',
['Bä']='Bärk:BAAALgAECgYJEQAAAA==.',
Ca='Cashile:BAAALgADCgUJBQAAAA==.',
Ce='Cedarjr:BAAALgAECgMJAwAAAA==.Cef:BAABLgAECn8gAAIRAAcJwRtyCAAtAgARAAcJwRtyCAAtAgAAAA==.Cefkru:BAAALgAECgYJDQABLgAECgcJIAARAMEbAA==.Cefloresence:BAAALgADCgQJBgAAAA==.Celesti:BAAALgADCgYJBgAAAA==.Celindre:BAAALgADCgkJJQAAAA==.Celyra:BAAALgADCgUJAwAAAA==.Cennial:BAAALgAECgMJAwAAAA==.',
Ch='Cheechee:BAAALgADCgIJAgAAAA==.Cherrybomb:BAAALgAECgIJAgAAAA==.Chewbie:BAABLgAECn8UAAISAAYJtiRvFAAXAgASAAYJtiRvFAAXAgAAAA==.Chippy:BAAALgADCgUJAgAAAA==.Chronobee:BAAALgAECgQJCwAAAA==.Chronolord:BAAALgAECgYJCwABLgAECggJGQAYAI4cAA==.',
Ci='Cirok:BAAALgAECgUJDAAAAA==.Cirya:BAAALgADCgMJAwAAAA==.Cisor:BAAALgAECgEJAQAAAA==.',
Ck='Cklyde:BAACLgAFFH8IAAIMAAMJtBXvEQDmAAAMAAMJtBXvEQDmAAAuAAQKfywAAwwACAlkIagFAI4CAAwACAlkIagFAI4CABIAAgn4INL6AJ4AAAAA.',
Cl='Claiyre:BAABLgAECn8UAAISAAYJxxVxRQA5AQASAAYJxxVxRQA5AQAAAA==.Clann:BAAALgAECgEJAQAAAA==.Cloudmaster:BAAALgADCgMJBQAAAA==.Clovermoon:BAAALgADCgMJAwAAAA==.Clubs:BAAALgAECgYJDQAAAA==.Clumperton:BAABLgAECn8YAAILAAkJBhZXGwBiAgALAAkJBhZXGwBiAgAAAA==.Clãsh:BAAALgAECgEJAQAAAA==.',
Co='Coalslaw:BAAALgADCgcJBwABLgAECggJIwAHAKweAA==.Coldrice:BAABLgAECn8YAAIJAAgJaCPfBQDDAgAJAAgJaCPfBQDDAgAAAA==.Concentrate:BAAALgAECggJIAAAAQ==.Connan:BAABLgAECn8hAAMZAAgJoSEHAgBxAgAaAAcJSSIhFACtAgAZAAgJ0h4HAgBxAgAAAA==.Corgän:BAAALgAECggJDAAAAA==.Coveness:BAAALgADCgYJDAAAAA==.Cowi:BAACLgAFFH8IAAIHAAMJGByLEgD7AAAHAAMJGByLEgD7AAAuAAQKfx0AAgcABwkRHNAmAPcBAAcABwkRHNAmAPcBAAAA.',
Cr='Crasusakechi:BAAALgAECgYJEwAAAA==.Crisisangel:BAABLgAECn8aAAMbAAcJVhlEBgC3AQAbAAcJYBdEBgC3AQABAAcJDhMhNACUAQAAAA==.',
Cu='Cuqquiform:BAAALgADCgEJAQAAAA==.',
Cy='Cylesia:BAAALgAECgYJDQAAAA==.Cylthia:BAAALgAECgIJAgAAAA==.',
Cz='Czaidan:BAAALgADCgIJAgAAAA==.',
Da='Daario:BAAALgADCgcJBwABLgADCgkJDwAKAAAAAA==.Dachi:BAAALgADCgUJBwAAAA==.Daemata:BAABLgAECn8UAAIcAAYJMgw4FQD8AAAcAAYJMgw4FQD8AAAAAA==.Dajinbo:BAAALgAECgUJEQAAAA==.Dalemist:BAAALgADCgEJAQAAAA==.Dancingbee:BAAALgADCgIJAgAAAA==.Dankinia:BAAALgADCgUJCgAAAA==.Danrith:BAAALgADCgQJBQAAAA==.Darkcat:BAAALgADCgUJCgAAAA==.Darkhammer:BAAALgAECgEJAQAAAA==.Darkkness:BAAALgADCgYJBgAAAA==.Darkswift:BAACLgAFFH8HAAISAAIJox+vHAC7AAASAAIJox+vHAC7AAAuAAQKfyUAAhIACAlhIvALAGkCABIACAlhIvALAGkCAAAA.Darnadda:BAAALgAECgEJAQAAAA==.Darowyn:BAABLgAECn8ZAAILAAgJBw0yJACKAQALAAgJBw0yJACKAQAAAA==.Darts:BAAALgAECgQJBAAAAA==.Dawnflare:BAABLgAECn8pAAMMAAgJPhqhGQBGAgAMAAgJPhqhGQBGAgASAAEJkAFuXgEfAAAAAA==.',
De='Deaxus:BAABLgAECn8hAAMdAAYJDBkZMQCaAQAdAAYJDBkZMQCaAQAIAAEJhw5nFwBEAAABLgAECggJJwAeAHINAA==.Deb:BAABLgAECn8UAAQFAAUJwBd9DgDRAAAWAAUJlhK1JQDVAAAFAAQJGxd9DgDRAAAfAAEJ0xEOMQBAAAAAAA==.Defacer:BAAALgADCgYJBgAAAA==.Dehdly:BAAALgAECgQJBQAAAA==.Delailia:BAAALgADCgUJBQAAAA==.Delbelfine:BAACLgAFFH8IAAIMAAMJSxdEEAD8AAAMAAMJSxdEEAD8AAAuAAQKfyoAAgwACAl0I8EEACADAAwACAl0I8EEACADAAAA.Delfar:BAAALgAECgYJCAAAAA==.Delietha:BAAALgAECgYJAgAAAA==.Dellechero:BAAALgADCgUJBQAAAA==.Demonbloodey:BAAALgAECgQJBAAAAA==.Demondred:BAAALgAECgQJBwAAAA==.Dethyler:BAABLgAECn8hAAIgAAgJjhlRAQAjAgAgAAgJjhlRAQAjAgAAAA==.Devilwoman:BAABLgAECn8XAAINAAcJbwPLUgCuAAANAAcJbwPLUgCuAAAAAA==.Deylil:BAAALgAECgUJCgAAAA==.Deyv:BAAALgADCgYJDQAAAA==.',
Di='Diddibeau:BAAALgAECgUJDAAAAA==.Dinkleburg:BAAALgAECgUJCgAAAA==.Dispayre:BAAALgADCgMJAwAAAA==.Divinezanon:BAAALgAECggJDgABLgAFFAQJDAACAH8dAA==.',
Do='Dontyagnomie:BAAALgAECgYJDgAAAA==.Dooganites:BAAALgAECgMJBAAAAA==.Dooganitis:BAABLgAECn8eAAISAAgJZB1GDQBZAgASAAgJZB1GDQBZAgAAAA==.Dorai:BAAALgAECgEJAgAAAA==.',
Dr='Dracken:BAAALgAECgUJBQAAAA==.Dracothian:BAAALgAECgYJDAAAAA==.Dragginballz:BAABLgAECn8gAAMVAAgJrx3jDgCIAgAVAAgJrx3jDgCIAgAUAAYJKxF4HABMAQAAAA==.Dragonwi:BAAALgAECgUJBQAAAA==.Drayden:BAAALgADCggJCAAAAA==.Drothiniàn:BAAALgAECgQJBAAAAA==.Drrush:BAABLgAECn8bAAISAAcJFA18VwAJAQASAAcJFA18VwAJAQAAAA==.Druix:BAAALgADCgUJBQAAAA==.Drulljin:BAAALgAECgUJCAAAAA==.',
Du='Dubu:BAAALgADCgMJBQAAAA==.Dusksorrow:BAAALgADCgEJAgAAAA==.',
['Dì']='Dìamond:BAAALgADCgMJAwAAAA==.',
Eb='Ebbyebby:BAAALgADCgcJBwAAAA==.',
Ed='Edovard:BAAALgAECgYJDAAAAA==.',
Ee='Eeragon:BAAALgAECgQJBwAAAA==.',
Ei='Eidolin:BAAALgADCgcJDQAAAA==.',
El='Electroo:BAAALgAECgUJCQAAAA==.Eleny:BAAALgAECgEJAQAAAA==.Elijáh:BAABLgAECn8jAAIQAAcJVhscCgDHAQAQAAcJVhscCgDHAQAAAA==.Ellarinya:BAAALgADCgUJCAAAAA==.Elmagoz:BAAALgADCgYJCQABLgAECgYJDwAKAAAAAA==.Elorahdanan:BAAALgADCgQJBAAAAA==.Elothien:BAAALgADCgYJBgAAAA==.Eltanari:BAAALgAECgYJDgAAAA==.Eluera:BAAALgAECgcJCAAAAA==.Elunelvr:BAAALgAECgYJDwAAAA==.Elyncute:BAAALgAECgYJDgABLgAFFAMJCAAJABcYAA==.Elynger:BAAALgAECgEJAQABLgAFFAMJCAAJABcYAA==.Elynthil:BAACLgAFFH8IAAMJAAMJFxgbLwAEAQAJAAMJFxgbLwAEAQAhAAEJQQncBgBRAAAuAAQKfyAAAwkACAlxILQPAEECAAkACAlxILQPAEECACIAAwl4BRE9AF8AAAAA.Elórn:BAABLgAECn8bAAISAAcJoxYeLgCJAQASAAcJoxYeLgCJAQAAAA==.',
Em='Emilie:BAAALgADCgUJBQAAAA==.Emolyywang:BAAALgADCgEJAQAAAA==.',
En='Endest:BAAALgADCgUJBQAAAA==.',
Ep='Epeener:BAAALgAECgMJAwABLgAECgYJGwAJAB0aAA==.Ephimonk:BAABLgAECn8XAAMRAAcJTB4xBwBKAgARAAcJTB4xBwBKAgAGAAEJ9hmIdABDAAAAAA==.',
Er='Erinnas:BAAALgAECgUJCQAAAA==.Erlaanda:BAAALgADCgYJBgAAAA==.',
Ev='Evelialia:BAAALgADCgYJDQAAAA==.',
Ey='Eyelock:BAAALgAECgEJAQAAAA==.',
Fa='Fastpunch:BAAALgADCgYJBgAAAA==.Fateweaver:BAABLgAECn8bAAQeAAgJEA1kJwCRAQAeAAgJEA1kJwCRAQAjAAEJAABGKQBNAAAkAAEJjAVvdgAuAAAAAA==.Fauce:BAAALgADCgkJCQAAAA==.',
Fe='Felblood:BAAALgAECgQJBgAAAA==.Feldel:BAAALgAECgUJCQAAAA==.Felthorne:BAAALgAECgIJAgAAAA==.Fenjie:BAAALgAECgcJEAAAAA==.Fenloras:BAAALgADCggJCQAAAA==.Ferndolyn:BAABLgAECn8ZAAICAAcJViCACgBhAgACAAcJViCACgBhAgAAAA==.Fezystorm:BAAALgADCgcJDAAAAA==.',
Fi='Firastraza:BAAALgADCgcJBwABLgAECgEJAQAKAAAAAA==.',
Fl='Flagonslayer:BAAALgADCgkJEAAAAA==.Flaime:BAAALgAECgYJDgAAAA==.Fluffystorm:BAAALgADCgkJGwAAAA==.Flur:BAAALgAECgIJAgAAAA==.',
Fo='Forzod:BAAALgAECgIJAwAAAA==.Foss:BAABLgAECn8aAAQaAAgJ5SAGEgDAAgAaAAgJ0iAGEgDAAgADAAYJMR6qGgB4AQAZAAEJ1RdsPgA7AAAAAA==.',
Fr='Freezerburn:BAACLgAFFH8IAAIBAAMJTBGVNAD+AAABAAMJTBGVNAD+AAAuAAQKfyoAAwEACAmBHUEZABQCAAEACAmBHUEZABQCACUAAQlvB1IRACwAAAAA.',
Fu='Furn:BAAALgADCgYJDgAAAA==.Furryaz:BAAALgAECgIJAgAAAA==.Furrydemon:BAAALgAECgMJBAAAAA==.',
Fy='Fyndros:BAAALgAECggJEAAAAA==.',
Ga='Gagà:BAAALgAECgYJAgAAAA==.Galaswen:BAABLgAECn8bAAILAAcJ+RUwIwCQAQALAAcJ+RUwIwCQAQAAAA==.Galavenat:BAABLgAECn8fAAMLAAcJ+ByzGgDAAQALAAcJ+ByzGgDAAQAXAAYJPQu5DwBkAQAAAA==.Galroy:BAAALgADCgMJAwAAAA==.Garbolicious:BAAALgADCgIJAgAAAA==.Garbothicc:BAAALgAECgUJDAAAAA==.Garnidelia:BAAALgAECggJEAAAAA==.Garyh:BAABLgAECn8nAAIaAAcJwiYeAwCmAgAaAAcJwiYeAwCmAgABLgAECggJGgAiAEQdAA==.Garyme:BAAALgADCgUJBQABLgAFFAUJFAACADkWAA==.Gaulvknight:BAAALgAECgEJAQAAAA==.Gazen:BAAALgADCgQJBAABLgAECgcJGwASABQNAA==.',
Ge='Geldeinmonch:BAAALgADCgkJGAABLgAECgcJGwAYAOsEAA==.Geldklerk:BAABLgAECn8bAAMYAAcJ6wSVJQDQAAAYAAcJ6wSVJQDQAAAmAAYJAAIQPQDDAAAAAA==.Gerado:BAABLgAECn8XAAImAAgJYAgMEQB9AQAmAAgJYAgMEQB9AQAAAA==.',
Gh='Ghuramak:BAAALgAECgQJBAAAAA==.',
Gi='Giacomo:BAAALgAECgUJDQAAAA==.Gildina:BAAALgAECgUJDQAAAA==.Ginggy:BAAALgAFFAEJAQAAAA==.Gingy:BAAALgAECgEJAQAAAA==.Girafficz:BAAALgAECgcJDgABLgAFFAgJHwAaAG4gAA==.',
Gl='Glognar:BAABLgAECn8ZAAILAAcJhgpwNAA/AQALAAcJhgpwNAA/AQAAAA==.',
Gn='Gnomernomnom:BAAALgADCgYJBgAAAA==.Gnorcci:BAAALgADCgEJAQAAAA==.',
Go='Gojo:BAAALgADCgMJAwAAAA==.Golgothan:BAAALgAECgUJBwAAAA==.Gori:BAABLgAECn8aAAMDAAcJERsuCAC1AQADAAcJERsuCAC1AQAaAAIJ/wUVmQBdAAAAAA==.Gork:BAAALgAECgQJBAAAAA==.Gortac:BAAALgAECgEJAQAAAA==.',
Gr='Gralle:BAAALgAECgcJEQAAAA==.Greyji:BAABLgAECn8fAAILAAgJJgxyOgDFAQALAAgJJgxyOgDFAQAAAA==.Greymonkey:BAABLgAECn8YAAILAAcJLhWtJwB5AQALAAcJLhWtJwB5AQAAAA==.Grimdy:BAAALgAECgYJAgAAAA==.Gryphinclaw:BAAALgADCgIJBAAAAA==.Grümb:BAACLgAFFH8GAAINAAMJvAsiJQDNAAANAAMJvAsiJQDNAAAuAAQKfyoAAg0ACAmXGCcVAMABAA0ACAmXGCcVAMABAAAA.',
Gu='Guenara:BAAALgAECggJHAABLgABCgQJBQAKAAAAAQ==.Guillimon:BAABLgAECn8UAAICAAgJARM2RQCNAQACAAgJARM2RQCNAQAAAA==.Gulitrom:BAAALgAECgYJCgAAAA==.Gurio:BAAALgAECgQJBAAAAA==.Gustytail:BAABLgAECn8ZAAIWAAcJ1AF9MACSAAAWAAcJ1AF9MACSAAAAAA==.',
Gz='Gzussaves:BAAALgAECgYJAgAAAA==.',
Ha='Haardrada:BAABLgAECn8aAAIiAAgJRB0qBQDlAQAiAAgJRB0qBQDlAQAAAA==.Habit:BAABLgAECn8hAAILAAgJqiHCCwDkAgALAAgJqiHCCwDkAgAAAA==.Hadrianna:BAABLgAECn8YAAIMAAgJOhlQDgD3AQAMAAgJOhlQDgD3AQAAAA==.Haimes:BAAALgAECgEJAQAAAA==.Halpono:BAAALgAECgEJAQAAAA==.Halrogue:BAAALgAECgYJAgAAAA==.Hanzul:BAABLgAECn8fAAQSAAgJXiNhBADYAgASAAgJXiNhBADYAgAnAAQJYhHPFADEAAAMAAEJnxE3lQA1AAAAAA==.Harcius:BAAALgADCgYJCAAAAA==.Hawkfoot:BAAALgAECgYJDQAAAA==.',
He='Helel:BAAALgADCgYJBgAAAA==.Hellanie:BAAALgAECgEJAQAAAA==.Hellbore:BAABLgAECn8oAAMfAAgJhRZXBADpAQAfAAgJhRZXBADpAQACAAIJ8Qf2tgBXAAAAAA==.Hellinasel:BAABLgAECn8bAAIJAAYJHRocNgBhAQAJAAYJHRocNgBhAQAAAA==.Hellishcrest:BAAALgADCgUJBQAAAA==.Hellrage:BAABLgAECn8bAAIDAAcJWR5gBgDpAQADAAcJWR5gBgDpAQAAAA==.Hellshocked:BAAALgADCgUJBQAAAA==.Hemmaeh:BAAALgADCgMJBQABLgAECgUJDAAKAAAAAA==.Hemmy:BAABLgAECn8iAAIMAAgJ8ybgAACSAwAMAAgJ8ybgAACSAwAAAA==.Hewbejeebees:BAAALgADCgEJAQAAAA==.Heywoo:BAAALgAECgQJBQAAAA==.Hezzakan:BAAALgAECgUJDQAAAA==.',
Hh='Hhnflaws:BAAALgADCgEJAQAAAA==.',
Hi='Hiding:BAAALgADCgEJAQAAAA==.',
Ho='Hobokianev:BAAALgADCgYJDQAAAA==.Holybonds:BAAALgAECgUJCAAAAA==.Hotspur:BAABLgAECn8ZAAIaAAcJ3wiPIQArAQAaAAcJ3wiPIQArAQAAAA==.',
Hu='Huevonyque:BAACLgAFFH8FAAIZAAIJoBkBCgC0AAAZAAIJoBkBCgC0AAAuAAQKfx8ABBkACAljIEkDANgCABkACAljIEkDANgCABoABgmDFkxSAGABAAMAAwkUDt4iAGQAAAAA.Hukkalno:BAAALgADCgEJAQAAAA==.Hundare:BAAALgADCgEJAQAAAA==.Huntsthewind:BAAALgAECgYJDgAAAA==.',
Hy='Hyejinx:BAAALgAECgMJBAAAAA==.',
Ic='Iceclaw:BAAALgAECgMJAwAAAA==.',
Id='Idana:BAAALgAECgEJAQAAAA==.Idkbry:BAAALgAECgMJBgAAAA==.',
Ih='Ihefret:BAAALgADCggJDQAAAA==.Ihiannan:BAAALgADCgkJFwABLgAECgcJGQAaAN8IAA==.',
Ii='Iiarian:BAABLgAECn8ZAAIWAAcJZhS4DwCXAQAWAAcJZhS4DwCXAQAAAA==.',
Il='Iliaih:BAAALgADCgEJAQABLgAECgYJCgAKAAAAAA==.Ilivarra:BAEALgAECgcJEQAAAA==.Illukana:BAABLgAECn8fAAMOAAgJ5hOiEwB4AQAOAAgJ5hOiEwB4AQAYAAIJewNmXQA/AAABLgAFFAUJEQASAHwfAA==.',
In='Inaura:BAAALgADCgUJBQABLgAECggJIwAHAKweAA==.Infoxy:BAAALgAECgYJCwAAAA==.Inkidu:BAAALgADCgkJEAAAAA==.Insanityalex:BAAALgAECgYJBwAAAA==.',
Ir='Irogram:BAABLgAECn8bAAIIAAcJGRh2BQDCAQAIAAcJGRh2BQDCAQAAAA==.',
Is='Isopope:BAAALgADCgkJCQAAAA==.Isthian:BAAALgAECgYJDAAAAA==.',
It='Itako:BAAALgADCggJDwAAAA==.Itoldhimso:BAAALgAECgUJEgAAAA==.',
Iu='Iudas:BAAALgAECgMJAwAAAA==.',
Iz='Izlan:BAAALgADCgcJBwAAAA==.',
Ja='Jabaho:BAAALgADCgUJBQAAAA==.Jadelark:BAAALgAECgYJDwAAAA==.Jahani:BAAALgADCgEJAQAAAA==.Jairus:BAAALgAECgQJCAAAAA==.Jammerwoch:BAABLgAECn8ZAAIoAAcJKCSkAQBXAgAoAAcJKCSkAQBXAgAAAA==.Jaxordamus:BAABLgAECn8fAAMeAAgJtBx+DQBBAgAeAAgJtBx+DQBBAgAjAAEJAAAyOAAaAAAAAA==.',
Je='Jekha:BAABLgAECn8bAAIlAAcJ7RafAQCzAQAlAAcJ7RafAQCzAQAAAA==.Jekle:BAAALgADCgUJBgAAAA==.Jema:BAAALgAECgYJEwAAAA==.Jengko:BAAALgAECgUJDAAAAA==.Jenilea:BAABLgAECn8ZAAIeAAcJJgk5RAAkAQAeAAcJJgk5RAAkAQAAAA==.',
Ji='Jimboree:BAABLgAECn8tAAIdAAkJJRqfBAB1AgAdAAkJJRqfBAB1AgAAAA==.Jinfae:BAAALgAECgYJAgAAAA==.Jinsu:BAAALgADCgkJKwAAAA==.Jinxyjinx:BAAALgADCgEJAQAAAA==.Jiujitsunut:BAAALgAECgIJAgAAAA==.',
Jo='Jordend:BAAALgAECgYJDQAAAA==.Joruana:BAAALgAECgEJAQAAAA==.Joseppii:BAAALgADCgQJBAAAAA==.',
Ju='Juiblexx:BAAALgAECgcJEAAAAA==.Junplague:BAAALgAECgUJDQAAAA==.Justamonk:BAAALgAECgkJBwAAAA==.',
Jy='Jynnx:BAAALgADCgUJCgAAAA==.Jyudas:BAAALgADCggJDQAAAA==.',
['Já']='Jámsap:BAAALgAECgQJCQABLgAECggJEAAKAAAAAA==.',
['Jå']='Jåzzy:BAAALgAECgYJEQAAAA==.',
Ka='Kaandew:BAAALgAECgUJDQAAAA==.Kaeras:BAAALgADCgkJCQAAAA==.Kaganost:BAAALgADCgYJBgAAAA==.Kailann:BAAALgADCgYJBgABLgADCgkJCQAKAAAAAA==.Kalord:BAAALgADCgEJAQAAAA==.Kaorin:BAAALgAECgUJCgAAAA==.Karesta:BAAALgAECgYJDgAAAA==.Karisiel:BAAALgAECgYJAgAAAA==.Kavix:BAAALgADCgEJAQAAAA==.Kaylith:BAAALgAECgYJDgAAAA==.Kayra:BAAALgAECgYJDAAAAA==.',
Ke='Keffka:BAABLgAECn8ZAAMHAAgJfhTnIQATAgAHAAgJfhTnIQATAgAdAAYJ5hcuPABcAQAAAA==.Kegelsmash:BAAALgAECgIJAwABLgAECgkJHgAFAFwjAA==.Kegwalker:BAABLgAECn8dAAMpAAgJ2x+bDQC5AgApAAgJ2x+bDQC5AgARAAIJFxRdMQCFAAAAAA==.Kelanansi:BAAALgAECgQJCQAAAA==.Keldorah:BAABLgAECn8iAAICAAgJNRk1CwBVAgACAAgJNRk1CwBVAgAAAA==.Kelel:BAAALgAFFAIJAwAAAA==.Kereth:BAAALgADCgIJAgAAAA==.Kessia:BAAALgAECgYJDAAAAA==.',
Kh='Khalistra:BAABLgAECn8eAAMUAAgJihKyBAB2AQAUAAgJ2xGyBAB2AQAVAAEJYBf5QgBGAAAAAA==.Khord:BAAALgAECgUJDQAAAA==.',
Ki='Kibeyna:BAAALgADCgQJAwAAAA==.Killdarabid:BAAALgADCgMJAwAAAA==.Kiropaly:BAAALgAECgQJCgAAAA==.Kirotard:BAAALgAECgQJBwABLgAECgQJCgAKAAAAAA==.Kisldarin:BAAALgAECgMJBgAAAA==.Kithedrael:BAAALgADCgcJCgAAAA==.',
Kl='Klexei:BAAALgADCgYJBgAAAA==.Klouded:BAABLgAECn8kAAIXAAgJKyKsAQCzAgAXAAgJKyKsAQCzAgAAAA==.',
Ko='Koa:BAAALgAECgUJBgAAAA==.Kojakk:BAABLgAECn8ZAAIJAAcJrBkDJACyAQAJAAcJrBkDJACyAQAAAA==.Kokuto:BAABLgAECn8pAAIDAAgJoRXgBwC8AQADAAgJoRXgBwC8AQAAAA==.Komak:BAAALgAECgYJAgAAAA==.Konjiki:BAAALgAECgcJEAAAAA==.Korvova:BAAALgADCgYJBgAAAA==.',
Kr='Krispybacon:BAAALgAECgMJAwAAAA==.Krêlas:BAAALgADCgEJAQAAAA==.',
Ku='Kulluast:BAAALgADCgcJBwAAAA==.Kuriana:BAAALgADCgEJAQAAAA==.Kursewalker:BAAALgADCgcJCQABLgAECggJHQApANsfAA==.',
Ky='Kyron:BAAALgADCgcJCAAAAA==.Kyttin:BAAALgADCgkJHQAAAA==.',
['Kä']='Kära:BAAALgAECgQJAwABLgAECggJIQAZAKEhAA==.',
La='Ladeeda:BAAALgADCgMJBwAAAA==.Lalena:BAAALgAECgYJEAAAAA==.Lamisa:BAABLgAECn8pAAQLAAgJ1yNjBAC6AgALAAgJ/SFjBAC6AgAXAAgJ7CIkAgCYAgAEAAQJrRpAWADlAAAAAA==.Lawanda:BAAALgADCgIJAgABLgAECgQJCAAKAAAAAA==.Lazlo:BAAALgADCgcJCAAAAA==.',
Le='Leib:BAAALgAECggJCgAAAA==.Leith:BAAALgADCgkJFgAAAA==.Lemmiwinks:BAAALgADCgcJDAAAAA==.Lenneth:BAAALgAECgUJCAAAAA==.Leoninelder:BAAALgADCgkJCQAAAA==.Leonineone:BAACLgAFFH8HAAIYAAMJ3RPfCwABAQAYAAMJ3RPfCwABAQAuAAQKfyoAAhgACAm9Ht0EAFICABgACAm9Ht0EAFICAAAA.',
Li='Lightlady:BAAALgAECgUJDQAAAA==.Lillythorne:BAAALgAECgYJEQAAAA==.Linas:BAAALgADCgcJDwAAAA==.Lindo:BAAALgAECgYJCAAAAA==.Lindsay:BAAALgAECgQJBAABLgAECgUJDAAKAAAAAA==.Lingsha:BAAALgAECgYJDwAAAA==.Litehlzonly:BAAALgAECgQJBAAAAA==.Liverando:BAAALgADCggJDgAAAA==.',
Lo='Lockchacho:BAAALgADCgcJCgAAAA==.Lockless:BAAALgADCgUJCAABLgAECgYJFQAVADAXAA==.Logosh:BAAALgADCgYJBgABLgAECgcJEAAKAAAAAA==.Lomilmand:BAAALgADCgUJCgAAAA==.Loststar:BAAALgAECgQJCAAAAA==.',
Lu='Luhspeaky:BAAALgAECgIJAgAAAA==.Luminosity:BAAALgADCgMJAwAAAA==.Lunalia:BAAALgAECgEJAgAAAA==.Lupen:BAAALgAECgYJBgAAAA==.Luxlock:BAABLgAECn8UAAMeAAYJcBK1PgA2AQAeAAUJrBG1PgA2AQAkAAIJchPsSwCKAAAAAA==.Luxxor:BAAALgAECgQJBAAAAA==.',
Ly='Lymiau:BAAALgADCgIJAgAAAA==.Lythala:BAAALgAECgYJDQAAAA==.',
['Lá']='Lárx:BAAALgAECgEJAQAAAA==.',
Ma='Mackirby:BAAALgADCgcJCgAAAA==.Macmoosaidh:BAAALgADCgMJAwAAAA==.Madison:BAAALgADCgYJBwAAAA==.Madjita:BAAALgADCgEJAQAAAA==.Magnetar:BAAALgAECgQJBwAAAA==.Magnusrn:BAAALgADCgUJCwAAAA==.Makudonarudo:BAABLgAECn8cAAIGAAgJFxqiFwAnAgAGAAgJFxqiFwAnAgAAAA==.Malandras:BAAALgAECgUJCAAAAA==.Malandrius:BAAALgAECgUJDQAAAA==.Malignities:BAAALgAECgYJCwAAAA==.Mallika:BAABLgAECn8YAAIBAAcJ9wRxawADAQABAAcJ9wRxawADAQAAAA==.Maltheradis:BAACLgAFFH8FAAIoAAMJ/g7fAgDFAAAoAAMJ/g7fAgDFAAAuAAQKfycAAigACQnsHnoDAJsCACgACQnsHnoDAJsCAAAA.Malthruin:BAAALgAECgYJCQABLgAECggJJwAeAHINAA==.Manajamba:BAABLgAECn8gAAMIAAgJzxWMBADkAQAIAAgJzxWMBADkAQAHAAEJdwEgrAAaAAAAAA==.Mancubus:BAABLgAECn8eAAISAAgJlRzrIgCeAgASAAgJlRzrIgCeAgAAAA==.Manorobrew:BAAALgADCgcJBwAAAA==.Marqazap:BAAALgADCgMJBAAAAA==.Marrexx:BAAALgAECgEJAQAAAA==.Maxidorf:BAAALgADCgkJEAAAAA==.',
Me='Meeoow:BAAALgAECgkJBAAAAA==.Megabite:BAAALgADCgUJBwAAAA==.Mellenna:BAAALgADCgMJAwABLgAECgcJEAAKAAAAAA==.Mergàtroid:BAAALgADCgkJCQAAAA==.Metatron:BAAALgADCgkJCQAAAA==.Meter:BAACLgAFFH8IAAISAAMJ3yMkEABGAQASAAMJ3yMkEABGAQAuAAQKfyAAAhIACAmgJvsDAI8DABIACAmgJvsDAI8DAAAA.Meush:BAACLgAFFH8RAAISAAUJfB/LAwC2AQASAAUJfB/LAwC2AQAuAAQKfx0AAhIACQkfJMgMACgDABIACQkfJMgMACgDAAAA.Mewkow:BAAALgAECgQJBwAAAA==.',
Mi='Miagoth:BAAALgAECgMJAwAAAA==.Midgee:BAAALgAECgYJDQAAAA==.Mindmuncher:BAAALgAECgUJCAAAAA==.Minimigraine:BAAALgADCgcJBwAAAA==.Miniroar:BAAALgADCgkJFAAAAA==.Minlai:BAAALgADCgkJCQAAAA==.Miphisto:BAAALgAECgYJCAAAAA==.Mirages:BAAALgAECgYJAgAAAA==.Mirandee:BAAALgAECgMJAwAAAA==.Mirranor:BAAALgADCgEJAQAAAA==.Misamyagi:BAABLgAECn8XAAIGAAgJBRNmDgCUAQAGAAgJBRNmDgCUAQAAAA==.Mishrani:BAAALgAECgUJDQAAAA==.Mixy:BAAALgAECgYJEAAAAA==.',
Mm='Mm:BAAALgADCgQJBAAAAA==.',
Mo='Molding:BAAALgADCggJDQAAAA==.Molleesi:BAABLgAECn8UAAITAAcJ4hLoCgBkAQATAAcJ4hLoCgBkAQAAAA==.Mollusk:BAAALgADCgUJCgAAAA==.Monril:BAAALgAECgQJBAAAAA==.Moodweaver:BAAALgADCgQJBAAAAA==.Moonstôrm:BAAALgAECgYJEQAAAA==.Mooyakasha:BAAALgAECgMJBAAAAA==.Mordraug:BAAALgAECgMJBgAAAA==.Morinoe:BAAALgAECgUJDAAAAA==.Mornwalker:BAABLgAECn8eAAMMAAgJmyAhAwDZAgAMAAgJmyAhAwDZAgAnAAEJKQSjTAAaAAAAAA==.',
Mu='Mumra:BAAALgAECggJDgAAAA==.Munchi:BAAALgADCgYJBgAAAA==.Murdermohawk:BAAALgADCggJCQAAAA==.',
My='Mynxiy:BAAALgADCggJDQAAAA==.Mystrian:BAAALgADCgMJAwAAAA==.',
['Mà']='Màdrigal:BAAALgADCgkJIAAAAA==.',
['Må']='Mål:BAAALgADCgEJAQAAAA==.',
['Mÿ']='Mÿthunn:BAABLgAECn8ZAAILAAYJTROyMgBGAQALAAYJTROyMgBGAQAAAA==.',
Na='Nact:BAAALgADCgUJCQAAAA==.Nagratz:BAABLgAECn8gAAIeAAcJ0xdMIQCuAQAeAAcJ0xdMIQCuAQAAAA==.Naichingeru:BAAALgADCgkJHQAAAA==.Nala:BAABLgAECn8pAAMCAAgJwBhQHwBGAgACAAgJwBhQHwBGAgAWAAcJPgdzHgAJAQAAAA==.Nalibrown:BAAALgAECgMJAwAAAA==.Napalmera:BAABLgAECn8SAAINAAgJqwUTWACgAAANAAgJqwUTWACgAAAAAA==.Napalmo:BAAALgADCgUJCgAAAA==.Naterra:BAAALgADCgkJCQAAAA==.Nathriezm:BAAALgAECgYJCwAAAA==.Naturalist:BAAALgAECgIJAgABLgAFFAQJBgAeAEcXAA==.Nayu:BAAALgAECgcJEAAAAA==.',
Ne='Necessities:BAABLgAECn8cAAIFAAgJwQhuDgDRAAAFAAgJwQhuDgDRAAAAAA==.Neirwind:BAAALgAECgMJBAAAAA==.Nekojin:BAAALgADCgMJAwABLgAECggJCAAKAAAAAA==.Nelithas:BAABLgAECn8cAAMNAAgJ7BpZNgAdAgANAAgJ7BpZNgAdAgAcAAQJsgwwSQDNAAAAAA==.Netrazomu:BAAALgADCgEJAQABLgAECgYJAgAKAAAAAA==.Newander:BAAALgADCgEJAQAAAA==.',
Ni='Nichiwa:BAAALgAECgQJBwAAAA==.Nicknock:BAAALgAECgQJBAAAAA==.Nightimelite:BAAALgAECgEJAQAAAA==.Nightimevzns:BAAALgAECgYJCwAAAA==.Niladros:BAAALgAECgEJAQAAAA==.Nisaam:BAAALgADCgQJBAAAAA==.Nishaya:BAABLgAECn8VAAIYAAcJkhNiJgCkAQAYAAcJkhNiJgCkAQAAAA==.',
No='Noamsky:BAABLgAECn8XAAMGAAgJihV1HQDuAQAGAAgJihV1HQDuAQARAAIJWQclYwBDAAABLgAFFAEJAQAKAAAAAA==.Nolmac:BAAALgAECgUJDQAAAA==.Nosleep:BAAALgADCgkJGAAAAA==.Notolf:BAAALgADCggJEAAAAA==.',
Nz='Nz:BAAALgADCgYJBgAAAA==.',
Ob='Obtusepanda:BAAALgAECgYJEQAAAA==.',
Of='Offthechaeni:BAAALgAECgUJDAAAAA==.',
Og='Ograndoe:BAABLgAECn8nAAInAAkJERcIBQDuAQAnAAkJERcIBQDuAQAAAA==.',
Oh='Ohku:BAAALgADCgUJAwAAAA==.Ohok:BAAALgAECgYJDwAAAA==.',
Oi='Oisin:BAAALgAECgUJDQAAAA==.',
Ol='Oleshawn:BAAALgADCgcJBgAAAA==.',
Om='Omathra:BAABLgAECn8nAAIeAAgJcg2MKwB+AQAeAAgJcg2MKwB+AQAAAA==.Omz:BAAALgAECgIJAgAAAA==.',
On='Onikai:BAABLgAECn8UAAIcAAcJ6RMLFwDoAAAcAAcJ6RMLFwDoAAAAAA==.Onruk:BAABLgAECn8VAAISAAcJPyWALwBlAgASAAcJPyWALwBlAgAAAA==.Onvarin:BAAALgADCgMJAwAAAA==.',
Op='Ophina:BAAALgADCgEJAQABLgAECgcJGAABAPcEAA==.',
Or='Orchestra:BAAALgAECgYJEgAAAA==.Orihime:BAAALgADCgEJAQAAAA==.',
Oz='Ozrah:BAAALgADCgkJCQAAAA==.',
Pa='Palacia:BAAALgAECgQJCAAAAA==.Paladullahan:BAABLgAECn8VAAIMAAYJmSTzBgByAgAMAAYJmSTzBgByAgAAAA==.Pandead:BAAALgAECgUJBQAAAA==.Panglossian:BAAALgADCgUJCgAAAA==.Paperbags:BAAALgAECgYJEAAAAA==.Parannor:BAAALgADCgMJAwAAAA==.Patadas:BAAALgAECgYJCAAAAA==.Pawthos:BAAALgAECgEJAQAAAA==.',
Pe='Pennonteller:BAAALgADCgYJDQAAAA==.Pewpewmcgraw:BAABLgAECn8fAAILAAgJZhYhFQDpAQALAAgJZhYhFQDpAQAAAA==.',
Ph='Phaanisaa:BAAALgADCgYJBgAAAA==.Phantsu:BAAALgADCgUJBQAAAA==.Phirix:BAAALgAECgcJDwAAAA==.Phreekish:BAAALgAECgcJCgAAAA==.',
Pi='Pinkkee:BAAALgADCgcJCwAAAA==.Pioniel:BAAALgAECgQJBAAAAA==.',
Pl='Plagueniss:BAACLgAFFH8IAAIDAAMJgx+rBwALAQADAAMJgx+rBwALAQAuAAQKfyoAAgMACAl6JCICAFEDAAMACAl6JCICAFEDAAAA.Pleu:BAAALgADCgkJGAAAAA==.',
Po='Pompino:BAAALgAECgYJDwAAAA==.',
Pr='Primè:BAAALgADCgcJDgAAAA==.Primø:BAAALgAECgQJBwAAAA==.Prometheuus:BAAALgADCgEJAQAAAA==.Prona:BAAALgADCgMJAwAAAA==.',
Ps='Psylancé:BAAALgAECgUJCQABLgAFFAMJCAACAE8NAA==.Psylänce:BAACLgAFFH8IAAICAAMJTw1dGgDIAAACAAMJTw1dGgDIAAAuAAQKfyoAAgIACAk1HXUKAGECAAIACAk1HXUKAGECAAAA.',
Pu='Puerile:BAAALgAECgYJAgAAAA==.Purplemoon:BAAALgADCgcJBwAAAA==.Purplêlotus:BAAALgAECgYJEwAAAA==.',
Py='Pyana:BAAALgAECgMJBgAAAA==.Pyke:BAAALgADCgIJAQAAAA==.',
Pz='Pz:BAAALgADCgIJAgAAAA==.',
Qs='Qserie:BAAALgAECgEJAQAAAA==.',
['Qü']='Qüeenmrgl:BAAALgADCgEJAQAAAA==.',
Ra='Rahner:BAAALgADCgYJCQAAAA==.Raidgriefer:BAAALgAECgIJAgAAAA==.Rainlac:BAAALgADCgMJAwAAAA==.Raistgar:BAAALgADCgcJBwABLgAECggJCAAKAAAAAA==.Raistlín:BAAALgAECgYJCQAAAA==.Rakwell:BAABLgAECn8cAAIiAAgJaxrbBQDQAQAiAAgJaxrbBQDQAQAAAA==.Ramil:BAABLgAECn8ZAAIHAAcJ+CRBAwDeAgAHAAcJ+CRBAwDeAgAAAA==.Ranchitup:BAAALgAECgMJAwAAAA==.Ravennadusk:BAAALgAECgMJBQAAAA==.Ravielly:BAAALgAECgYJBgAAAA==.Rawhide:BAAALgAECgQJBAAAAA==.',
Re='Reannis:BAAALgAECgQJCQAAAA==.Reanukeeves:BAAALgADCgUJBwAAAA==.Redmaple:BAAALgADCgcJCwABLgAECgUJDAAKAAAAAA==.Refaim:BAAALgADCgMJAwAAAA==.Rekane:BAAALgAECgQJCAAAAA==.Renala:BAAALgADCgkJFgAAAA==.Reteril:BAABLgAECn8rAAILAAgJGyLYBwB7AgALAAgJGyLYBwB7AgAAAA==.Reyis:BAAALgAECgYJEQAAAA==.Reyvinite:BAABLgAECn8gAAISAAgJkxBiKAChAQASAAgJkxBiKAChAQAAAA==.Rezdemonia:BAAALgAECgYJDgAAAA==.',
Rh='Rhadigan:BAAALgAECgYJBgAAAA==.Rhodaria:BAAALgAECgYJDgAAAA==.Rhyme:BAAALgAECgUJDAABLgAFFAMJCAASAN8jAA==.',
Ri='Rimesoul:BAAALgADCgcJBwAAAA==.Rissu:BAAALgAECgYJBwAAAA==.',
Rk='Rk:BAAALgAECgMJAwAAAA==.',
Ro='Roasted:BAAALgAECgYJEAAAAA==.Roka:BAAALgAECgIJAwAAAA==.Rook:BAAALgAECgcJEQAAAA==.Rousou:BAABLgAECn8bAAIBAAcJhBk1KADEAQABAAcJhBk1KADEAQAAAA==.',
Ru='Rukia:BAABLgAECn8mAAMYAAgJHyBbBABjAgAYAAgJHyBbBABjAgAOAAYJtBsyKACuAQAAAA==.',
Ry='Ryoushen:BAACLgAFFH8IAAQXAAMJ+gphCwDsAAAXAAMJzgdhCwDsAAAEAAIJGAexIQCIAAALAAEJOwdpPABOAAAuAAQKfysAAgQACAk6HQADAAgCAAQACAk6HQADAAgCAAAA.Ryssha:BAAALgAECgYJDgAAAA==.',
Sa='Sadie:BAAALgADCgYJCwAAAA==.Sailla:BAAALgAECgEJAQAAAA==.Sanori:BAAALgADCgYJBgAAAA==.Sapphism:BAACLgAFFH8MAAMEAAcJMhYTBAD9AQAEAAcJmhQTBAD9AQAXAAEJKSKVEQBnAAAuAAQKfx0AAwQACQk/I68FAEADAAQACQk6IK8FAEADABcACAnyIzULAK0BAAAA.Sarai:BAAALgADCgcJEQAAAA==.Sarbio:BAAALgAECgYJDwAAAA==.Sargrim:BAAALgAECgQJBAAAAA==.Sarrma:BAAALgADCgkJHwAAAA==.Saskwatch:BAAALgAECgIJAgABLgAFFAEJAQAKAAAAAA==.Saturnïne:BAAALgAECgQJBwAAAA==.Savare:BAAALgAECgYJAgAAAA==.Savat:BAAALgAECggJCAABLgAECgYJDwAKAAAAAA==.',
Sc='Scargazer:BAAALgADCgUJBQAAAA==.Sckratchxx:BAAALgAECgcJEgAAAA==.Scoochacho:BAABLgAECn8gAAIBAAcJiyRfDACBAgABAAcJiyRfDACBAgAAAA==.Scp:BAAALgADCgEJAQAAAA==.Scyithe:BAAALgADCgMJAwAAAA==.',
Se='Sei:BAAALgADCgYJBgAAAA==.Sendrax:BAAALgAECgYJEwAAAA==.Senhunter:BAAALgAECgYJCAAAAA==.Senmaster:BAAALgADCgkJCQAAAA==.',
Sh='Shadowdáddy:BAABLgAECn8eAAMXAAgJeQYlEQBQAQAXAAgJeQYlEQBQAQALAAMJIAIHxgA/AAAAAA==.Shadowtarget:BAAALgAECgYJEQAAAA==.Shakers:BAABLgAECn8kAAILAAgJ6B57EgCjAgALAAgJ6B57EgCjAgAAAA==.Shamarq:BAAALgADCgcJGQAAAA==.Shandrahli:BAAALgAECgEJAQAAAA==.Shawnobi:BAAALgAECgYJDwAAAA==.Shayla:BAABLgAECn8VAAICAAYJHR54FADiAQACAAYJHR54FADiAQAAAA==.Shaylina:BAAALgAECgUJDAAAAA==.Shayrdas:BAAALgADCggJDAAAAA==.Shintazhi:BAAALgAECgUJDAAAAA==.Shirkan:BAABLgAECn8dAAIaAAgJrhxODADpAQAaAAgJrhxODADpAQAAAA==.Shleva:BAAALgADCgYJEAAAAA==.Shojobeat:BAAALgAECgcJDgAAAA==.Shone:BAABLgAECn8iAAISAAkJhhYwDwBFAgASAAkJhhYwDwBFAgAAAA==.Shopify:BAAALgAECgUJCQAAAA==.Shutai:BAAALgADCgEJAQAAAA==.Shynn:BAAALgAECgIJAgAAAA==.',
Si='Silalatha:BAAALgAECgUJCgAAAA==.Sindrii:BAAALgAECgMJAwAAAA==.Sinhoi:BAAALgADCggJCAABLgAECgMJAwAKAAAAAA==.Sinku:BAAALgAECgIJAgAAAA==.Sinza:BAAALgADCgcJCwABLgAECgIJAgAKAAAAAA==.Sisterego:BAAALgAECgUJCAAAAA==.',
Sk='Skadooshh:BAAALgAECgUJDAABLgAECggJIQAZAKEhAA==.Skeeterwingz:BAAALgADCgEJAQABLgAECggJGgAiAEQdAA==.Skewinkatoo:BAAALgAECgYJAgAAAA==.Skorf:BAEBLgAECn8bAAQTAAcJ4Qr9EgDLAAATAAYJRgr9EgDLAAAUAAcJPQMVCwC3AAAVAAMJ1APTVQBrAAAAAA==.',
Sl='Slidetheboof:BAAALgAECgQJBgAAAA==.',
Sm='Smoothmoves:BAAALgAECgEJAQAAAA==.',
Sn='Sneakylash:BAAALgAECgYJEAAAAA==.Snickersnack:BAAALgADCgEJAQAAAA==.Snyph:BAAALgAECgEJAQAAAA==.',
So='Soohainao:BAAALgAECgUJCQABLgAFFAMJCAABALAVAA==.Sorador:BAAALgADCgYJBgAAAA==.Soup:BAABLgAECn8WAAIGAAgJcCBUCQDiAgAGAAgJcCBUCQDiAgAAAA==.Soysauce:BAAALgAFFAEJAQABLgAFFAUJEgABAHAeAA==.',
Sp='Spairibou:BAAALgAECgcJDQAAAA==.Spellgibson:BAABLgAECn8pAAIBAAgJKSSXBgDPAgABAAgJKSSXBgDPAgAAAA==.Spiara:BAAALgAECgYJCgAAAA==.Spicypizza:BAAALgAECgYJEAABLgAFFAUJEQAhAMUaAA==.Spinathan:BAAALgAECgUJCQABLgAECgYJFAAHAMEgAA==.Spludge:BAABLgAECn8XAAIEAAgJtQxFDwDWAAAEAAgJtQxFDwDWAAAAAA==.Spudd:BAAALgADCgYJBgAAAA==.Spyroh:BAABLgAECn8VAAMVAAYJMBcxFABgAQAVAAYJRhYxFABgAQAUAAQJUxEyKQDWAAAAAA==.',
Sq='Squirrél:BAAALgADCgUJBQAAAA==.',
St='Stormbrook:BAABLgAECn8VAAIdAAYJ8BaJFgBgAQAdAAYJ8BaJFgBgAQAAAA==.Stravyn:BAEBLgAECn8cAAMnAAgJkh6TBwBkAgAnAAcJPiCTBwBkAgASAAIJDxTzuQBEAAAAAA==.Stumpnose:BAAALgADCgYJBwAAAA==.Sturmdorf:BAAALgAECgUJDQAAAA==.Stórmy:BAAALgADCgYJEQAAAA==.',
Su='Suhli:BAAALgAECgkJBAAAAA==.Sulfrick:BAAALgADCggJGwAAAA==.Sulpher:BAAALgADCgcJDgAAAA==.Summannuz:BAAALgADCgcJDgAAAA==.',
Sw='Sweetchi:BAAALgAECgYJEQAAAA==.',
Sy='Sybria:BAAALgAECgYJCAAAAA==.Sykko:BAABLgAECn8hAAIBAAgJhiC8MgCoAgABAAgJhiC8MgCoAgAAAA==.Symet:BAAALgADCgYJCwAAAA==.',
Ta='Taarsha:BAAALgAECgYJCAAAAA==.Tabb:BAAALgADCgQJBwAAAA==.Tache:BAAALgAECgYJEQAAAA==.Taera:BAAALgAECgEJAQAAAA==.Taisetsu:BAACLgAFFH8IAAIpAAMJDwJLHwCgAAApAAMJDwJLHwCgAAAuAAQKfyoAAikACAlcEXYSAHcBACkACAlcEXYSAHcBAAAA.Takhisis:BAAALgADCgIJAwAAAA==.Tal:BAEALgAECgYJDAABLgAECggJHAAnAJIeAA==.Talin:BAAALgAECgcJBQAAAA==.Tamagoyaki:BAAALgADCgUJBwAAAA==.Tannastia:BAAALgAECgUJAQAAAA==.Tarlas:BAABLgAECn8ZAAIMAAYJUwvWJAAgAQAMAAYJUwvWJAAgAQAAAA==.Tayllore:BAABLgAECn8VAAIBAAcJjgSFbQD/AAABAAcJjgSFbQD/AAAAAA==.',
Te='Tearsheet:BAAALgAECgEJAQABLgAECgcJGQAaAN8IAA==.Tehsneakyone:BAAALgADCgcJCwABLgAECgcJGQAJAKwaAA==.Terendelev:BAABLgAECn8mAAITAAgJrhKMCQCFAQATAAgJrhKMCQCFAQAAAA==.Terrador:BAAALgAECgIJAgAAAA==.Terramortua:BAACLgAFFH8GAAIJAAMJOyVOGgBMAQAJAAMJOyVOGgBMAQAuAAQKfxwAAgkACAlGJSIIAJsCAAkACAlGJSIIAJsCAAAA.Terraviridis:BAABLgAECn8XAAIWAAcJlCPVEACYAgAWAAcJlCPVEACYAgAAAA==.',
Th='Thaanatus:BAABLgAECn8ZAAIJAAcJmQwhgQCAAQAJAAcJmQwhgQCAAQAAAA==.Thalassairi:BAAALgAECgUJDAAAAA==.Thaldin:BAAALgADCggJDQAAAA==.Thaleris:BAAALgAECgQJCwAAAA==.Thaugtless:BAAALgADCgUJBQABLgAECgYJFQAVADAXAA==.Theglf:BAAALgAECgIJAwAAAA==.Thelonious:BAAALgAECgMJCAAAAA==.Thelonius:BAAALgAECgIJAgAAAA==.Theodorum:BAAALgADCgYJBgAAAA==.Therocksays:BAAALgAECgYJEwAAAA==.Thessaly:BAAALgADCgcJBwAAAA==.Thinloc:BAABLgAECn8kAAMeAAgJZRhAFQD7AQAeAAgJnBZAFQD7AQAkAAUJjRaOHgBcAQAAAA==.Thrandruin:BAABLgAECn8VAAINAAcJ6Am6QADkAAANAAcJ6Am6QADkAAAAAA==.Thranduill:BAAALgADCgYJBgAAAA==.Thronjak:BAABLgAECn8QAAIJAAYJmR2ULQCFAQAJAAYJmR2ULQCFAQAAAA==.',
Ti='Tidêpod:BAAALgAECgQJBAAAAA==.Tikka:BAAALgADCgkJFAAAAA==.Tilly:BAAALgAECgEJAQAAAA==.Timbermane:BAAALgAECgYJEQAAAA==.Timmie:BAAALgAECgEJAQABLgAECggJJAAXACsiAA==.Tinyriik:BAABLgAECn8mAAIeAAgJ2xFSHgC+AQAeAAgJ2xFSHgC+AQAAAA==.Tippietows:BAAALgADCgYJDQAAAA==.Tipride:BAAALgAECgMJAwABLgAFFAMJCAABALAVAA==.Tiralie:BAAALgAECgQJBQAAAA==.Tiryl:BAAALgAECgYJCwAAAA==.',
Tn='Tnama:BAAALgADCgcJDQAAAA==.',
To='Togashi:BAAALgAECgYJBgAAAA==.Tomodachi:BAAALgAECgYJEwAAAA==.Tonantius:BAAALgADCgMJAwAAAA==.Toogodly:BAABLgAECn8XAAIMAAgJpB9/DAAPAgAMAAgJpB9/DAAPAgAAAA==.Torent:BAAALgAECgYJDgAAAA==.Toshinori:BAAALgAECgIJAgAAAA==.',
Tr='Tribulus:BAABLgAECn8YAAINAAgJJgpfLAAzAQANAAgJJgpfLAAzAQAAAA==.Trikki:BAAALgADCgMJAwAAAA==.Trinogra:BAAALgAECgYJAgAAAA==.Trishbellows:BAAALgADCgkJDQAAAA==.Trissers:BAAALgAECgMJBAAAAA==.Trystern:BAAALgAECgYJDwAAAA==.',
Tu='Turqos:BAAALgADCgkJIAAAAA==.',
Tw='Twilie:BAAALgAECgYJBgAAAA==.',
Ty='Tyrala:BAAALgAECgEJAwAAAA==.',
['Tä']='Tänya:BAAALgAECgYJDwAAAA==.',
Uh='Uhoh:BAAALgAECgEJAQAAAA==.',
Ul='Ultar:BAABLgAECn8pAAISAAgJhyI+CgB9AgASAAgJhyI+CgB9AgAAAA==.Ultodeemagic:BAAALgAECgMJAwAAAA==.Ultotracker:BAAALgAECgUJCQAAAA==.',
Un='Ungrant:BAAALgAECgMJAgAAAA==.Unvdi:BAAALgAECgQJBAAAAA==.',
Uz='Uzani:BAABLgAECn8cAAISAAgJhRMdHgDVAQASAAgJhRMdHgDVAQAAAA==.',
Va='Vaderrage:BAABLgAECn8ZAAMaAAgJYB1pFACqAgAaAAgJFx1pFACqAgAZAAEJAhTDKABFAAAAAA==.Valeyria:BAAALgAECgYJDAAAAA==.Valino:BAABLgAECn8VAAIWAAYJhiAMDQC8AQAWAAYJhiAMDQC8AQAAAA==.Valri:BAAALgAECgUJCgAAAA==.Valtari:BAAALgADCgMJBAAAAA==.Vancasper:BAAALgAECgMJBAAAAA==.Vaol:BAABLgAECn8XAAMFAAcJpAkPHQC6AAAFAAYJ9AkPHQC6AAAfAAMJAQUlGwBHAAAAAA==.Varae:BAAALgADCgEJAQAAAA==.Varidall:BAAALgADCgEJAQAAAA==.Varll:BAAALgAECgcJEQABLgAFFAMJCAANAMkdAA==.Varlvdh:BAACLgAFFH8IAAINAAMJyR0qGAAUAQANAAMJyR0qGAAUAQAuAAQKfywAAw0ACAlvJLAFAIUCAA0ACAlvJLAFAIUCACgAAQlzDz0vACMAAAAA.Vaxeen:BAAALgADCgYJBgAAAA==.',
Ve='Velanas:BAAALgADCgIJAgAAAA==.Velf:BAAALgAECggJDgAAAA==.Velmathris:BAAALgAECgcJDQAAAA==.Velorya:BAAALgADCgMJAwAAAA==.Ventnor:BAAALgADCgcJCgAAAA==.Veuamr:BAAALgAECgEJAQAAAA==.Veydh:BAAALgAECggJCwAAAA==.Veywing:BAAALgAECgMJBAAAAA==.',
Vi='Vickademus:BAAALgADCgIJAgAAAA==.Viinnee:BAABLgAECn8fAAIOAAgJaB0iAwC5AgAOAAgJaB0iAwC5AgAAAA==.Vincentlight:BAAALgAECgYJCgAAAA==.Vintorez:BAAALgAECgUJBgAAAA==.Viralmaster:BAEALgAECggJDQAAAA==.Vixess:BAACLgAFFH8IAAIYAAMJvhSBCwAFAQAYAAMJvhSBCwAFAQAuAAQKfyoABBgACAlIHjsKAN0BABgABwmwITsKAN0BACYACAmPCQcUAFgBAA4AAgmgBpBzAFoAAAAA.',
Vo='Voidweaver:BAABLgAECn8ZAAIYAAgJjhydBQA8AgAYAAgJjhydBQA8AgAAAA==.Volteer:BAAALgAECgYJDwAAAA==.Vorloc:BAAALgAECgYJAgAAAA==.',
Vu='Vudor:BAAALgAECgMJAwAAAA==.',
Vy='Vyara:BAAALgAECgUJDAAAAA==.Vynddradoria:BAABLgAECn8iAAQkAAgJbh4uBQCHAgAkAAgJ1B0uBQCHAgAjAAUJGhdxBQAvAQAeAAIJGBNl7gB9AAAAAA==.Vyndh:BAAALgAECgUJDgAAAA==.Vynlock:BAACLgAFFH8IAAMeAAMJ1x9rIQAbAQAeAAMJRx1rIQAbAQAkAAIJZiBtCQDBAAAuAAQKfyoAAx4ACAkOJf0GAJ0CAB4ACAkOJf0GAJ0CACQABgnFI9IHAEgCAAAA.Vynstaya:BAAALgAECgEJAQAAAA==.Vyxaya:BAAALgAECgYJCgAAAA==.',
Wa='Wabe:BAAALgAECgUJBwAAAA==.Walkman:BAAALgAECgEJAQAAAA==.Wanderin:BAAALgAECgYJEAAAAA==.Wanderit:BAAALgADCgUJBQAAAA==.Waysmomtwo:BAAALgAECgMJBAAAAA==.',
Wh='Whatthehelle:BAAALgADCgEJAQAAAA==.Whiskerses:BAABLgAECn8ZAAIJAAcJrBriMgBtAQAJAAcJrBriMgBtAQAAAA==.Whithers:BAAALgAECgYJDgAAAA==.',
Wi='Wildwrath:BAAALgADCgMJAwAAAA==.Wilyy:BAAALgAECgMJBAABLgAECgYJEwAKAAAAAA==.Windman:BAAALgAECgIJAgABLgAECggJGAARAGgMAA==.Wingsofgold:BAAALgADCgMJBAAAAA==.Wintergreen:BAAALgADCgYJDgAAAA==.Wiseblossom:BAABLgAECn8ZAAICAAgJpCB1CQD7AgACAAgJpCB1CQD7AgAAAA==.Wisha:BAAALgAECgQJBAAAAA==.',
Wo='Woodsylver:BAAALgAECgUJCgAAAA==.Worski:BAAALgAECgQJBwAAAA==.',
Wr='Wrathael:BAAALgAECgQJDAABLgAECgYJBgAKAAAAAA==.Wratherael:BAAALgADCgUJBQABLgAECgYJBgAKAAAAAA==.Wrathiechan:BAAALgAECgYJBgAAAA==.Wraîth:BAAALgAECgcJBAAAAA==.',
Wu='Wurdiz:BAAALgADCggJEgABLgAECgcJGQAaAN8IAA==.',
Wy='Wynilla:BAAALgAECgUJDQAAAA==.',
Wz='Wz:BAAALgADCgMJAwAAAA==.',
Xa='Xalori:BAAALgADCgYJBwAAAA==.Xanathar:BAABLgAECn8aAAIBAAgJlxbFJwDGAQABAAgJlxbFJwDGAQAAAA==.Xaphoris:BAAALgADCgMJAwAAAA==.Xayleficent:BAAALgADCgQJBwAAAA==.Xaylia:BAAALgADCgQJBQAAAA==.',
Xe='Xenkore:BAAALgAECgIJAgAAAA==.Xenolith:BAAALgADCggJCAAAAA==.Xerial:BAAALgAECgYJBgABLgAECgYJDwAKAAAAAA==.Xermonk:BAAALgADCgQJBAAAAA==.',
Xi='Xinul:BAAALgAECgYJEgAAAA==.',
Xu='Xuelia:BAAALgADCgYJBgAAAA==.',
Ya='Yaoxt:BAAALgAECgYJDwAAAA==.Yassi:BAABLgAECn8bAAICAAcJSw+ZLwAfAQACAAcJSw+ZLwAfAQAAAA==.',
Ye='Yeahlux:BAAALgAECgcJBwAAAA==.',
Yn='Ynk:BAAALgAECgcJCwAAAA==.',
Yu='Yura:BAAALgADCgUJDAAAAA==.Yurius:BAAALgADCgQJCQABLgAECgIJAgAKAAAAAA==.',
Yv='Yvane:BAAALgADCgMJAwAAAA==.Yvonnel:BAAALgAECgcJEAAAAA==.',
Za='Zaghary:BAABLgAECn8fAAIoAAgJwhArBwBMAQAoAAgJwhArBwBMAQAAAA==.Zanduran:BAAALgAECgQJBwAAAA==.Zaos:BAAALgADCgYJCwAAAA==.Zaraza:BAAALgADCgUJBgAAAA==.Zarik:BAAALgADCgcJEwAAAA==.',
Ze='Zensorrow:BAAALgAECgEJAQAAAA==.Zerial:BAAALgADCgYJDgAAAA==.',
Zh='Zhammonk:BAAALgADCgUJCAAAAA==.Zhend:BAAALgAECgYJEQAAAA==.Zhuei:BAAALgAECgkJAgAAAA==.',
Zi='Ziggeh:BAAALgAECgIJAgAAAA==.Zindrozarat:BAAALgAECgUJBQAAAA==.Zinshanpu:BAAALgADCgMJBAAAAA==.',
Zp='Zpaatos:BAAALgAECgcJDQAAAA==.',
Zu='Zunch:BAAALgAECgEJAQAAAQ==.Zunra:BAAALgAECgMJBgAAAA==.',
Zv='Zviperr:BAAALgAECgMJAwAAAA==.',
Zy='Zygry:BAAALgADCgYJCwAAAA==.',
['Àz']='Àzazel:BAABLgAECn8jAAIcAAgJ9RKHDAB0AQAcAAgJ9RKHDAB0AQAAAA==.',
['Át']='Átropos:BAAALgAECgQJBgAAAA==.',
['Är']='Ärmistice:BAAALgADCgMJAwABLgAECgMJAwAKAAAAAA==.',
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
