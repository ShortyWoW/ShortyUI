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

local lookup = {'Hunter-BeastMastery','DeathKnight-Unholy','Mage-Frost','Druid-Restoration','Paladin-Holy','Evoker-Augmentation','Priest-Holy','Priest-Shadow','Hunter-Survival','Unknown-Unknown','Warrior-Fury','Druid-Balance','Paladin-Retribution','Monk-Brewmaster','Hunter-Marksmanship','Paladin-Protection','Warlock-Demonology','Druid-Guardian','Shaman-Restoration','Shaman-Elemental','DemonHunter-Vengeance','Monk-Windwalker','Monk-Mistweaver','Priest-Discipline','Shaman-Enhancement','DemonHunter-Devourer','Warlock-Affliction','Warlock-Destruction','Rogue-Subtlety','DeathKnight-Blood','DemonHunter-Havoc','Warrior-Arms','Evoker-Preservation','Warrior-Protection','Mage-Arcane','DeathKnight-Frost','Evoker-Devastation','Rogue-Outlaw','Rogue-Assassination','Druid-Feral',}
local provider = {region='US',realm='Elune',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aanallein:BAAALgAECgEJAQAAAA==.',
Ae='Aeithir:BAAALgAECgEJAQAAAA==.Aerwin:BAAALgAECgEJBQAAAA==.Aesterid:BAAALgAECgEJAQAAAA==.Aethyr:BAAALgAECgYJCgAAAA==.',
Af='Afflictor:BAAALgAECggJBAAAAA==.',
Ai='Aidivh:BAAALgAECgEJAQAAAA==.',
Ak='Akashah:BAABLgAECn8bAAIBAAcJ3AhuPwAYAQABAAcJ3AhuPwAYAQAAAA==.Akeno:BAABLgAECn8dAAICAAcJxCB5IADFAQACAAcJxCB5IADFAQAAAA==.Akhen:BAABLgAECn8dAAIDAAgJYx9OFQAxAgADAAgJYx9OFQAxAgAAAA==.',
Al='Alarick:BAAALgAECgUJDwAAAA==.Alatha:BAAALgAECgMJBAABLgAECggJIwADAPIcAA==.Alathasedai:BAABLgAECn8jAAIDAAgJ8hwOFAA6AgADAAgJ8hwOFAA6AgAAAA==.Alathea:BAAALgAFFAIJAgAAAA==.Alayil:BAAALgAECgUJDQAAAA==.Aledis:BAACLgAFFH8FAAICAAIJFB58RQC3AAACAAIJFB58RQC3AAAuAAQKfy4AAgIACQlmJOsBADEDAAIACQlmJOsBADEDAAAA.Alexaera:BAAALgADCgUJBQAAAA==.Algeni:BAAALgAECgEJAQAAAA==.Alissa:BAAALgADCgMJAwAAAA==.Allanøn:BAAALgAECgUJCQAAAA==.Almuqit:BAABLgAECn8eAAIBAAcJKR1gEgD/AQABAAcJKR1gEgD/AQAAAA==.Alphaba:BAAALgADCgQJBwAAAA==.Alyrical:BAABLgAECn8UAAIEAAcJNRfkRwCDAQAEAAcJNRfkRwCDAQAAAA==.',
Am='Amalith:BAAALgAECgcJAQAAAA==.Amowrath:BAABLgAECn8dAAIFAAcJqw/5GQB9AQAFAAcJqw/5GQB9AQAAAA==.Amyasia:BAAALgAECgcJEwAAAA==.Amyxia:BAAALgAECgUJBQAAAA==.Amára:BAAALgAECgYJBwAAAA==.',
An='Anaaru:BAAALgADCgEJAgAAAA==.Andrai:BAAALgADCgMJAwAAAA==.Animax:BAAALgAECgEJAwAAAA==.Animethighs:BAAALgAECgUJCQAAAA==.Anitajones:BAAALgAECgIJBQAAAA==.Annaleth:BAAALgAECgYJCgAAAA==.Annieoakley:BAAALgADCgQJBAAAAA==.',
Ao='Aoski:BAAALgADCgYJBgABLgAECgYJFQAGAM0HAA==.',
Aq='Aquaskies:BAAALgAECggJDgAAAA==.',
Ar='Aradoa:BAABLgAECn8dAAMHAAgJ7xCjKwCZAQAHAAgJ7xCjKwCZAQAIAAYJWBHCLQBxAQAAAA==.Arashin:BAAALgAECgQJBgAAAA==.Arawn:BAAALgADCgMJAwAAAA==.Arkmonk:BAAALgAECgQJCQAAAA==.Arknight:BAABLgAECn8VAAIJAAgJkRLWEwCHAQAJAAgJkRLWEwCHAQAAAA==.Arlynn:BAAALgADCgEJAQAAAA==.Artemysia:BAAALgADCgkJCwAAAA==.Arturía:BAABLgAECn8bAAIJAAgJVB6JAwDtAgAJAAgJVB6JAwDtAgABLgAFFAEJAQAKAAAAAA==.Arylin:BAAALgAECgIJAgAAAA==.Arysa:BAAALgAECgIJAgAAAA==.',
As='Astartes:BAABLgAECn8UAAILAAgJ/xm0JwAfAgALAAgJ/xm0JwAfAgAAAA==.Astoria:BAABLgAECn8jAAIMAAgJZBJ7JADZAQAMAAgJZBJ7JADZAQAAAA==.Astreae:BAAALgAECgYJBwAAAA==.Astreri:BAAALgADCgcJCwABLgAECgQJBwAKAAAAAA==.',
Au='Augmentation:BAAALgADCgYJBgAAAA==.Aundil:BAAALgADCgYJBgAAAA==.',
Av='Aveline:BAAALgAECgMJAwAAAA==.Avi:BAAALgAECgYJBwABLgAECggJFQACACkhAA==.Avoir:BAAALgADCgEJAQAAAA==.Avrathrael:BAAALgAECgEJAQAAAA==.',
Ax='Axos:BAABLgAECn8dAAINAAgJlRTdHgDQAQANAAgJlRTdHgDQAQAAAA==.Axxe:BAAALgADCgMJAwAAAA==.',
Ay='Aya:BAAALgAECggJEQAAAA==.Ayekillu:BAAALgAFFAEJAQAAAA==.Ayiasofia:BAABLgAECn8gAAIHAAcJwh4CEQBbAgAHAAcJwh4CEQBbAgAAAA==.Ayire:BAABLgAECn8VAAIBAAYJeRp8JACJAQABAAYJeRp8JACJAQAAAA==.Ayla:BAABLgAECn8eAAIOAAcJaAPdJADhAAAOAAcJaAPdJADhAAAAAA==.Aylan:BAABLgAECn8YAAIOAAcJ9xTWEwBnAQAOAAcJ9xTWEwBnAQABLgAECgcJCwAKAAAAAA==.Aylian:BAAALgADCgkJEgABLgAECgcJCwAKAAAAAA==.Ayumfox:BAABLgAECn8VAAQBAAgJCh2dCgBUAgABAAgJChydCgBUAgAPAAMJ4hXxFQCAAAAJAAEJZQrXLgA+AAAAAA==.Ayumm:BAAALgAECgYJDwAAAA==.',
Az='Azapal:BAABLgAECn8dAAMQAAgJChyjBwBjAgAQAAgJrxqjBwBjAgANAAcJuhh3bAClAQAAAA==.Azarialilith:BAAALgADCgEJAQAAAA==.Aztez:BAAALgADCgMJAwAAAA==.Azuremagi:BAAALgAECgEJAQAAAA==.Azures:BAAALgADCgcJCAAAAA==.Azuros:BAAALgAECgcJDAAAAA==.Azzorael:BAAALgAECgYJCQAAAA==.',
['Aë']='Aëmeath:BAABLgAECn8ZAAIIAAcJcB3QEQBtAgAIAAcJcB3QEQBtAgAAAA==.',
Ba='Badger:BAABLgAECn8gAAILAAgJkSL5BABwAgALAAgJkSL5BABwAgAAAA==.Balloon:BAAALgAECgYJBgAAAA==.Balthotros:BAAALgAECgMJAwABLgAECgcJGQALADkgAA==.Bandâid:BAAALgADCgcJDAABLgAECgQJBQAKAAAAAA==.Barathiel:BAACLgAFFH8HAAIBAAMJZQX0HgDcAAABAAMJZQX0HgDcAAAuAAQKfzEAAgEACAkTHMwMADgCAAEACAkTHMwMADgCAAAA.Barlow:BAAALgAECgUJDgAAAA==.Baryll:BAABLgAECn8bAAIFAAYJBBQ7HQBgAQAFAAYJBBQ7HQBgAQAAAA==.Bathei:BAAALgADCgkJDwAAAA==.Battlebruver:BAAALgAECgUJCAAAAA==.',
Bc='Bc:BAEALgADCgcJBwABLgAECggJGAARAPgmAA==.',
Be='Beardude:BAAALgADCgIJAQAAAA==.Bearserkêr:BAAALgADCgYJBgAAAA==.Bellitrix:BAAALgADCgkJFwAAAA==.Bellne:BAAALgAECgUJCQAAAA==.',
Bi='Biefcake:BAABLgAECn8gAAICAAgJ+w2DLQCFAQACAAgJ+w2DLQCFAQAAAA==.Bigmoo:BAABLgAECn8yAAISAAkJmxkoAwAbAgASAAkJmxkoAwAbAgAAAA==.Billnye:BAAALgADCgYJBgAAAA==.Bimbi:BAAALgADCgQJBAABLgAECgMJAwAKAAAAAA==.Biscoff:BAAALgAECgMJAwAAAA==.Bizmatec:BAAALgAECgQJBAAAAA==.',
Bl='Blackparade:BAAALgAECgYJDwAAAA==.Bladesong:BAAALgADCgMJAgAAAA==.Blaydon:BAAALgAECgYJDAAAAA==.Blayusa:BAAALgAECgUJCAABLgAECgYJDAAKAAAAAA==.Blended:BAAALgAECgIJAgAAAA==.Bloodancient:BAAALgADCgEJAwAAAA==.Blush:BAAALgAECgQJBAAAAA==.',
Bo='Boiledfrogz:BAABLgAECn8dAAMMAAgJ3RgNJADdAQAMAAgJ3RgNJADdAQAEAAQJIRuiLAAuAQAAAA==.Bolognese:BAAALgAECgUJCwAAAA==.Boned:BAACLgAFFH8NAAIBAAQJYSDlBgBuAQABAAQJYSDlBgBuAQAuAAQKfyoAAwEACQlrIh0BAKQDAAEACQlrIh0BAKQDAA8AAgn1AEGBAEEAAAAA.Boopboops:BAABLgAECn8WAAMTAAcJiBhyMQDBAQATAAcJiBhyMQDBAQAUAAMJFRBwawCVAAAAAA==.Bootybreeze:BAAALgADCgEJAgAAAA==.Bottombear:BAAALgADCgYJCQAAAA==.',
Br='Bravehearthx:BAAALgAECgcJDgAAAA==.Breija:BAAALgADCgYJGQAAAA==.Bringerdk:BAAALgAECgQJEAAAAA==.Bringerlk:BAAALgAECgQJBAAAAA==.Bringerp:BAAALgAECgQJDgAAAA==.Brogend:BAAALgAECgYJBwABLgAECggJIAALAJEiAA==.Brohym:BAAALgAECgUJCQAAAA==.Brokki:BAAALgAECgIJBAAAAA==.Bronwyn:BAAALgAECgYJEAAAAA==.Brúh:BAAALgAECgMJAwAAAA==.',
Bu='Buffiey:BAAALgADCgcJHQAAAA==.Bugjug:BAAALgADCgIJAQAAAA==.Butterdish:BAAALgAECgEJAQABLgAECgkJFgAVAJMNAA==.',
Bz='Bz:BAAALgADCgIJAgAAAA==.',
Ca='Caféconron:BAAALgAECgEJAQAAAA==.Caitsidhe:BAABLgAECn8VAAISAAgJtwUNIACfAAASAAgJtwUNIACfAAAAAA==.Cannan:BAAALgAECgEJAwAAAA==.Cannute:BAAALgAECgYJEAAAAA==.Canuckdemon:BAAALgADCgEJAQAAAA==.Canuckdruid:BAAALgADCgQJBAAAAA==.Canuckranger:BAAALgAECgIJBAAAAA==.Canucksham:BAAALgADCggJCAAAAA==.Captnubcakes:BAABLgAECn8ZAAILAAcJOSAgDgDSAQALAAcJOSAgDgDSAQAAAA==.Capziestrian:BAABLgAECn8hAAQOAAgJsRt7CwDRAQAOAAgJsRt7CwDRAQAWAAMJqBLjUgDGAAAXAAIJthQaVgB3AAAAAA==.Carathir:BAAALgAECgIJAQABLgAFFAUJEwAWALgeAA==.Carefreè:BAACLgAFFH8TAAIWAAUJuB6nAgB2AQAWAAUJuB6nAgB2AQAuAAQKfyQAAhYACQk1JBgBALcDABYACQk1JBgBALcDAAAA.Castallia:BAABLgAECn8bAAQYAAgJJhnmEgAaAgAYAAgJJhnmEgAaAgAIAAgJMBN0EQB9AQAHAAIJugi+dABWAAAAAA==.Catrathena:BAAALgAECgYJEgAAAA==.',
Cd='Cdxanti:BAAALgAFFAEJAQAAAA==.Cdxdrags:BAAALgADCgYJCQABLgAFFAEJAQAKAAAAAA==.',
Ce='Celeborn:BAAALgADCgYJDAAAAA==.Celeg:BAAALgAECgEJAQAAAA==.Celestine:BAAALgAECgEJAQAAAA==.Celithel:BAAALgAECgEJAQAAAA==.Celta:BAAALgADCgIJAgAAAA==.Celunelle:BAAALgADCgkJDwAAAA==.Cerulia:BAAALgADCgYJBgAAAA==.',
Ch='Chadgar:BAAALgAECgEJBQAAAA==.Chamanita:BAABLgAECn8cAAITAAcJ6RYqFwCtAQATAAcJ6RYqFwCtAQAAAA==.Chaospho:BAABLgAECn8jAAIXAAcJKhzbDQDIAQAXAAcJKhzbDQDIAQAAAA==.Charizzard:BAAALgADCgIJAgAAAA==.Charmelle:BAAALgADCgEJAQAAAA==.Chewbåcca:BAAALgADCgEJAQAAAA==.Cheweh:BAACLgAFFH8MAAMZAAQJPQ1QAwD/AAAZAAQJPQ1QAwD/AAAUAAEJawBBJgA2AAAuAAQKfxkAAxkACQlkIAcHAH8CABkACQlkIAcHAH8CABQAAglJEIY8AHMAAAAA.Cheysuli:BAAALgADCgQJBAAAAA==.Choson:BAABLgAECn8aAAILAAcJHgrOGwBSAQALAAcJHgrOGwBSAQAAAA==.Chronô:BAAALgAECgcJEgAAAA==.Chudlee:BAAALgAECgYJEwAAAA==.Chumsticktwo:BAABLgAECn8UAAIaAAgJqRDUGgCTAQAaAAgJqRDUGgCTAQAAAA==.',
Ci='Cirillaa:BAAALgAECgcJDwAAAA==.Citi:BAAALgAECgQJBgAAAA==.Citinight:BAAALgADCgEJAQAAAA==.',
Cl='Clair:BAABLgAECn8kAAIHAAgJsh6EDQCAAgAHAAgJsh6EDQCAAgAAAA==.Clandestiny:BAAALgADCgIJAgAAAA==.Clef:BAAALgADCgcJBwAAAA==.Cleris:BAAALgAECgIJAgAAAA==.Cloudburstt:BAABLgAECn8aAAITAAcJSBjyEQDiAQATAAcJSBjyEQDiAQAAAA==.Clova:BAAALgAECgcJEgAAAA==.Clëric:BAAALgAECgIJAwAAAA==.',
Co='Coler:BAAALgAECgYJDAAAAA==.Conelley:BAAALgADCgcJEAABLgADCgkJDwAKAAAAAA==.Conservative:BAAALgADCgEJAQAAAA==.Cooldan:BAABLgAECn8VAAQRAAcJVhxQHgC+AQARAAcJxRpQHgC+AQAbAAEJaBhcKgBKAAAcAAEJ8wwGcAA2AAAAAA==.Cooldude:BAAALgAECgYJCgAAAA==.',
Cr='Crabetable:BAABLgAECn8YAAMZAAgJoAfUCABfAQAZAAgJoAfUCABfAQATAAEJ2QF2pAArAAAAAA==.Crankinette:BAAALgADCgMJAwAAAA==.Creation:BAAALgADCgcJCgAAAA==.Cremefraiche:BAAALgAECggJEgAAAA==.Critkiller:BAAALgADCgQJBAAAAA==.Crocodile:BAAALgADCgYJBwAAAA==.Crowsiv:BAAALgAECgkJEwAAAA==.Crulzilla:BAABLgAECn8ZAAICAAcJLxUQMQB1AQACAAcJLxUQMQB1AQAAAA==.',
Cu='Cupcakemeeow:BAABLgAECn8UAAIDAAYJSwZRbwD7AAADAAYJSwZRbwD7AAABLgAECggJFwABAIMPAA==.Cupcakemeow:BAABLgAECn8XAAQBAAgJgw/sMQDoAQABAAgJgw/sMQDoAQAPAAIJeQLuhQA2AAAJAAIJFASdMQA0AAAAAA==.Curas:BAAALgAECgQJAwAAAA==.Curzøn:BAABLgAECn86AAIDAAkJvSXcAwAGAwADAAkJvSXcAwAGAwAAAA==.Cutecumber:BAAALgADCgQJBQABLgADCgYJDAAKAAAAAA==.',
Cy='Cynardria:BAABLgAECn8hAAIEAAgJwiTOBgAfAwAEAAgJwiTOBgAfAwAAAA==.Cynaris:BAAALgADCgEJAQAAAA==.',
['Cí']='Cínnabon:BAAALgADCgkJDwAAAA==.',
Da='Dabubblez:BAAALgADCgcJBwAAAA==.Daedengerek:BAABLgAECn8hAAILAAgJAxfqEACyAQALAAgJAxfqEACyAQAAAA==.Daggers:BAAALgADCgQJBAAAAA==.Daggren:BAABLgAECn8YAAIdAAYJfxOMFgAkAQAdAAYJfxOMFgAkAQAAAA==.Daiko:BAAALgAECgMJAwAAAA==.Danazaral:BAAALgAECgYJEgAAAA==.Danerrin:BAABLgAECn8cAAMCAAgJVyFcCgB9AgACAAgJ1yBcCgB9AgAeAAcJeh7jAwANAgAAAA==.Dangermonk:BAAALgADCgEJAQAAAA==.Dangers:BAAALgAECgEJAQAAAA==.Danielsan:BAAALgAECgEJAQAAAA==.Danigos:BAAALgAFFAgJHwAAAQ==.Danocosmic:BAAALgAECgIJBAAAAA==.Danofyst:BAAALgADCgIJAgAAAA==.Danuwoa:BAABLgAECn8gAAIeAAgJLhJ7GQCIAQAeAAgJLhJ7GQCIAQAAAA==.Darkarrows:BAAALgADCgYJBgAAAA==.Darkritual:BAAALgADCgcJDgAAAA==.Daryss:BAAALgAECgIJAwAAAA==.Dawnshott:BAAALgAECggJCAAAAA==.Dawntotem:BAAALgADCgkJCgAAAA==.Dax:BAAALgADCgEJAQAAAA==.Daxoman:BAAALgAECgYJCgAAAA==.Daxxen:BAAALgADCgYJBgAAAA==.Daynkmyst:BAAALgADCgMJBQAAAA==.',
De='Deathadder:BAABLgAECn8gAAIBAAgJSiJKBQClAgABAAgJSiJKBQClAgAAAA==.Deathslayer:BAAALgAECgkJAgAAAA==.Deemonk:BAAALgAECggJCAAAAA==.Deification:BAAALgAECgUJEwAAAA==.Delaena:BAAALgAECggJEQAAAA==.Delron:BAAALgAECgEJAQAAAA==.Delvari:BAAALgADCgEJAQAAAA==.Demins:BAAALgAECgQJCAAAAA==.Demiphant:BAAALgADCgcJBwAAAA==.Demonballz:BAAALgAECgYJDwAAAA==.Demonickirby:BAAALgADCgkJCQAAAA==.Denarrin:BAAALgAECgQJCgABLgAECggJHAACAFchAA==.Dennirn:BAAALgADCgIJAgABLgAECggJHAACAFchAA==.Deport:BAAALgADCgYJBgAAAA==.',
Di='Dianesis:BAAALgADCgYJBgAAAA==.Dieclowns:BAAALgAECgEJAQAAAA==.Dirtcat:BAAALgADCgIJAgAAAA==.Disgrace:BAAALgAECgEJAQAAAA==.Divínity:BAAALgAECgMJBAAAAA==.',
Do='Doomboome:BAAALgADCgkJEgAAAA==.Downstime:BAAALgAECgMJAwAAAA==.',
Dr='Dracthar:BAAALgAECgQJBQAAAA==.Draczeal:BAAALgAECgYJEwAAAA==.Dragonoffel:BAABLgAECn8UAAMRAAcJvwyxNABYAQARAAcJvwyxNABYAQAbAAEJAAAjFQAAAAAAAA==.Dragovade:BAABLgAECn8kAAQUAAgJshZ9DQDGAQAUAAgJshZ9DQDGAQATAAIJ1hKYSwBvAAAZAAEJ3wpAGQA4AAAAAA==.Drathor:BAABLgAECn8hAAIRAAcJ1B06OQAnAgARAAcJ1B06OQAnAgAAAA==.Dravauk:BAAALgADCgQJBAAAAA==.Dreamtotem:BAAALgADCgEJAQAAAA==.Druishbeef:BAAALgAECgQJBAAAAA==.Drunkenbuddy:BAAALgAECgIJAgAAAA==.Drunky:BAAALgAECgYJEwAAAA==.Drysua:BAABLgAECn8rAAIIAAkJ0hZCFgA2AgAIAAkJ0hZCFgA2AgAAAA==.',
Dz='Dzret:BAABLgAECn8xAAINAAYJKxEUVAASAQANAAYJKxEUVAASAQAAAA==.',
['Dà']='Dàx:BAAALgAECgYJEQABLgAECgkJOgADAL0lAA==.',
['Dá']='Dáewoo:BAAALgADCgUJBQAAAA==.',
['Dè']='Dècypher:BAABLgAECn8fAAIUAAgJNBj2CQD7AQAUAAgJNBj2CQD7AQAAAA==.',
['Dí']='Díana:BAAALgADCgIJAgAAAA==.',
Ec='Echô:BAABLgAECn8WAAINAAYJfQW1awDYAAANAAYJfQW1awDYAAAAAA==.Echôes:BAAALgAECgEJAQAAAA==.',
Ed='Edbundance:BAAALgAFFAIJAgAAAA==.',
El='Ela:BAABLgAECn8VAAINAAgJiA/6mQBKAQANAAgJiA/6mQBKAQAAAA==.Elanuo:BAAALgAECgQJBwAAAA==.Elarisiel:BAAALgADCgkJDgAAAA==.Elaynne:BAABLgAECn8hAAMPAAcJmCQIEAC7AgAPAAcJfCMIEAC7AgABAAYJ6CDmFADrAQAAAA==.Eledis:BAABLgAECn8cAAMfAAgJQhlnCQCtAQAfAAgJQhlnCQCtAQAVAAIJuBDpJABcAAAAAA==.Elieth:BAAALgADCgUJBQAAAA==.Eliteelf:BAABLgAECn8cAAIPAAgJawUxDQD5AAAPAAgJawUxDQD5AAAAAA==.Ellenora:BAABLgAECn8cAAMEAAgJjgsWJABiAQAEAAgJjgsWJABiAQAMAAIJggHxgQAuAAAAAA==.Ellessdee:BAAALgAECgYJDwAAAA==.Ellmer:BAABLgAECn8fAAIBAAcJqx99FACTAgABAAcJqx99FACTAgAAAA==.Elopeppe:BAAALgAECgYJEwAAAA==.Elorro:BAACLgAFFH8JAAILAAUJAgk3CABqAQALAAUJAgk3CABqAQAuAAQKfyYAAwsACAmlHoMSALsCAAsACAn3HYMSALsCACAAAwnQGtAoAKkAAAAA.Eltaizari:BAAALgADCgQJBAAAAA==.Elthiör:BAAALgADCgEJAQAAAA==.Eltion:BAAALgADCgMJAwAAAA==.Elwesingollo:BAAALgADCgcJDwAAAA==.',
En='Enilia:BAACLgAFFH8KAAMcAAMJpB2YCQC+AAARAAMJlxXnKQD3AAAcAAIJ2B+YCQC+AAAuAAQKfycAAxwACAlLH/8AAGUCABwACAneHv8AAGUCABEAAwk7FApmAMQAAAAA.Enrgizernelf:BAAALgAECgUJDwAAAA==.',
Er='Erathena:BAAALgAECgYJBgAAAA==.Eriya:BAAALgAECgYJEgAAAA==.',
Es='Esmeray:BAABLgAECn8dAAIdAAgJ7xJFCgDFAQAdAAgJ7xJFCgDFAQAAAA==.',
Et='Eternîty:BAAALgAECgcJAgAAAA==.',
Eu='Euphonia:BAAALgAECgUJDgAAAA==.',
Ev='Eviantha:BAAALgADCgYJBgAAAA==.',
Ex='Excieo:BAAALgAECgUJBQAAAA==.Exgimm:BAAALgAECgEJAQAAAA==.Exinani:BAAALgAECgEJAQAAAA==.Exkira:BAAALgADCgEJAQAAAA==.',
Ey='Eyllis:BAABLgAECn8oAAIHAAgJ9hEHEgCMAQAHAAgJ9hEHEgCMAQAAAA==.',
Ez='Ezekiel:BAAALgADCgMJAwAAAA==.',
Fa='Faedark:BAAALgAECgEJAQAAAA==.Falcios:BAAALgADCgYJCQAAAA==.Falcor:BAAALgAECgUJBwAAAA==.Falorin:BAAALgADCgkJCwAAAA==.Fancyface:BAAALgAECgMJBQABLgAECgUJCgAKAAAAAA==.Fanger:BAABLgAECn8WAAQZAAYJ8haSDgDoAAAZAAUJ1BmSDgDoAAAUAAUJbwd6WgDaAAATAAIJGwUAjwBbAAAAAA==.Fatthead:BAAALgADCgIJAgAAAA==.Faug:BAABLgAECn8UAAIhAAcJPwvILAANAQAhAAcJPwvILAANAQAAAA==.Fax:BAABLgAECn8UAAIXAAcJ3hG5MQAwAQAXAAcJ3hG5MQAwAQAAAA==.',
Fe='Fecalbutt:BAAALgADCgUJBQAAAA==.Ferang:BAABLgAECn8iAAMCAAcJDxc5bwCqAQACAAcJHhQ5bwCqAQAeAAcJoRQ2FQDXAAAAAA==.Fevion:BAAALgAECgQJBAABLgAECgYJCgAKAAAAAA==.',
Ff='Ffredyburger:BAAALgAECgEJAQAAAA==.',
Fi='Finduilas:BAABLgAECn8jAAMiAAcJiiGeBgDiAQAiAAcJiiGeBgDiAQALAAQJhwOGhACsAAAAAA==.Fingaz:BAAALgAECgYJEQAAAA==.Firepower:BAABLgAECn8aAAMjAAcJ8xx1AwA3AgAjAAYJHyJ1AwA3AgADAAcJLBYPOACHAQAAAA==.Firepriest:BAAALgAECgYJEQAAAA==.Fistdard:BAAALgADCgIJAgAAAA==.Fistymisty:BAAALgAECgQJCAAAAA==.Fiôwyn:BAAALgADCgcJBwAAAA==.',
Fl='Flashspam:BAAALgAECgYJDwAAAA==.',
Fo='Foamcutout:BAAALgAECgcJDgAAAA==.Foog:BAABLgAECn8dAAIEAAgJLiKTFQCKAgAEAAgJLiKTFQCKAgAAAA==.Fourteen:BAACLgAFFH8SAAIXAAYJJyBcAQAxAgAXAAYJJyBcAQAxAgAuAAQKfyQAAhcACQmmIq4CAFsDABcACQmmIq4CAFsDAAAA.Fourus:BAAALgADCgcJBwAAAA==.',
Fr='Freakaleake:BAABLgAECn8WAAMNAAYJSw/SYwDrAAANAAYJSw/SYwDrAAAQAAEJPA9rJwA0AAAAAA==.Fredburger:BAAALgAECgQJBAAAAA==.Freemochi:BAAALgADCgEJAQABLgAFFAUJDwARAFIQAA==.Freeport:BAAALgAECgUJBQABLgAFFAUJDwARAFIQAA==.Freesum:BAACLgAFFH8PAAIRAAUJUhDAFgA5AQARAAUJUhDAFgA5AQAuAAQKfyMAAhEACAnaIQESAOsCABEACAnaIQESAOsCAAAA.Friweelin:BAAALgADCgEJAQAAAA==.Frostypillz:BAAALgADCgEJAQAAAA==.',
Fu='Fulgor:BAACLgAFFH8SAAIEAAYJxR29AgDEAQAEAAYJxR29AgDEAQAuAAQKfzkAAgQACQlZJZ0AAKUDAAQACQlZJZ0AAKUDAAAA.Funnymuffin:BAABLgAECn8fAAMcAAgJmBZiAwC7AQAcAAgJmBZiAwC7AQARAAEJ2QQyvAAtAAAAAA==.Furyia:BAAALgAECgUJCAAAAA==.Fuzzleprime:BAABLgAECn8kAAISAAgJ2xVCBQC5AQASAAgJ2xVCBQC5AQAAAA==.Fuzzy:BAAALgAECgUJEwAAAA==.',
Ga='Galatea:BAAALgAECgUJBgABLgAFFAEJAQAKAAAAAA==.Gannin:BAAALgADCgEJAQABLgAECgEJAQAKAAAAAA==.Garmart:BAABLgAECn8jAAQJAAkJPByrAQCzAgAJAAkJWRurAQCzAgABAAkJCxe7CgBSAgAPAAcJaBOZLQDBAQAAAA==.Gauza:BAAALgAECgYJEwAAAA==.',
Ge='Geb:BAAALgADCgkJCQAAAA==.Genga:BAAALgADCgQJBAAAAA==.',
Gh='Ghostlyone:BAAALgADCgYJBgAAAA==.Ghouldann:BAABLgAECn8dAAMcAAgJXxiqBACKAQAcAAgJgxeqBACKAQARAAYJjxFjpwAKAQAAAA==.Ghòstdòg:BAAALgAECgQJCAAAAA==.',
Gi='Gilday:BAAALgAECgQJDQAAAA==.',
Gl='Glagglag:BAABLgAECn8gAAILAAgJRRzpDADhAQALAAgJRRzpDADhAQAAAA==.Glasscannon:BAAALgAECgQJBwAAAA==.',
Go='Gohâm:BAAALgAECgMJAwAAAA==.Goosefuyuki:BAAALgADCgMJAwAAAA==.Gorothraex:BAABLgAECn8WAAIiAAcJoxx5CACvAQAiAAcJoxx5CACvAQAAAA==.',
Gr='Grailand:BAAALgAECgYJBwAAAA==.Graxion:BAABLgAECn8eAAILAAcJ/w9NFgCBAQALAAcJ/w9NFgCBAQAAAA==.Greggiiee:BAAALgAECgUJCQAAAA==.Grimdots:BAAALgADCgkJCgAAAA==.Grimlock:BAAALgADCgcJBwAAAA==.Grimmkrieger:BAAALgAECgIJAwAAAA==.Grimtusk:BAAALgAECgEJAQAAAA==.Grimzz:BAAALgAECgEJAQAAAA==.Grindelwald:BAAALgADCgkJLwAAAA==.',
Gu='Guak:BAAALgAECgMJBAAAAA==.Guakalock:BAAALgADCgcJEQAAAA==.Guernica:BAAALgADCgIJAgAAAA==.Gurfy:BAEALgADCgUJBQAAAA==.Guylos:BAAALgADCgcJEgAAAA==.',
Gw='Gwynorra:BAAALgAECgUJCAAAAA==.',
Gy='Gyradas:BAAALgAECgkJBwAAAA==.',
Ha='Habibi:BAABLgAECn8VAAIdAAgJchJbKgCpAQAdAAgJchJbKgCpAQAAAA==.Hampter:BAAALgADCggJCAAAAA==.Hanwi:BAAALgADCgYJBwAAAA==.Haralda:BAABLgAECn8VAAMCAAgJUQbJugANAQACAAYJFwfJugANAQAkAAIJZASADgBOAAAAAA==.Haraluna:BAAALgADCgUJBQAAAA==.Harlequín:BAAALgADCgcJDgABLgADCgkJDwAKAAAAAA==.Harshblue:BAABLgAECn8gAAMNAAcJpyR0FADwAgANAAcJpyR0FADwAgAQAAQJvR96GABRAQAAAA==.Hasdormu:BAAALgADCgQJBAABLgAECgEJAQAKAAAAAA==.Hatsunixbay:BAAALgADCggJDgAAAA==.Hatt:BAABLgAECn8UAAMNAAcJvgzVgAB4AQANAAcJvgzVgAB4AQAQAAUJZQhALgCeAAAAAA==.',
Hd='Hdmiport:BAABLgAECn8WAAIVAAkJkw29DQB6AQAVAAkJkw29DQB6AQAAAA==.',
He='Hebrews:BAAALgADCgMJAwAAAA==.Heddh:BAAALgAECgQJBAABLgAECggJIQAEAMIkAA==.Heilen:BAAALgADCgIJAgAAAA==.Heiligfeuer:BAAALgAECgIJBAAAAA==.Hellscorn:BAABLgAECn8jAAIaAAcJRQv3QADjAAAaAAcJRQv3QADjAAAAAA==.Herrick:BAAALgAECgkJAgAAAA==.Heythanksman:BAABLgAECn8VAAILAAYJuiL7KQASAgALAAYJuiL7KQASAgAAAA==.Heyzues:BAAALgADCgMJBgABLgAECgUJCwAKAAAAAA==.',
Hi='Hippay:BAAALgAECgUJEwAAAA==.',
Ho='Hoid:BAABLgAECn8bAAMLAAcJKRQAFgCDAQALAAcJNRMAFgCDAQAgAAIJ5xLTLgB/AAAAAA==.Holynihalus:BAACLgAFFH8JAAIHAAQJjxhVBABCAQAHAAQJjxhVBABCAQAuAAQKfx0AAgcACQkUHy0IAMgCAAcACQkUHy0IAMgCAAAA.Holyph:BAAALgADCgEJAQAAAA==.Holysmacker:BAAALgADCgIJAgAAAA==.Holyspoons:BAABLgAECn8xAAINAAgJBhOkJgCpAQANAAgJBhOkJgCpAQAAAA==.',
Hu='Huggs:BAAALgAECgYJCAAAAA==.Hunterama:BAAALgADCgcJCQAAAA==.Huntli:BAABLgAECn8tAAIBAAkJGCG/AQALAwABAAkJGCG/AQALAwAAAA==.Hurthar:BAAALgADCgIJAgAAAA==.',
Hy='Hylaa:BAAALgADCgcJEQAAAA==.Hyrill:BAAALgADCgcJCgAAAA==.',
['Hé']='Hécate:BAABLgAECn8gAAIXAAgJyB02BQB/AgAXAAgJyB02BQB/AgAAAA==.',
Ic='Icecreamcake:BAACLgAFFH8aAAMHAAYJ6xMJAQDnAQAHAAYJ6xMJAQDnAQAYAAMJLgAdHwBIAAAuAAQKfyMAAwcACQnxDkscAPsBAAcACQnxDkscAPsBAAgABgm/EGo3ADMBAAAA.',
If='Ifingerpaint:BAAALgAFFAEJAgABLgAFFAYJDwAIAFkaAA==.',
Ik='Ikin:BAAALgADCggJEgAAAA==.',
Il='Illidansdad:BAAALgAECgcJCwAAAA==.',
Im='Imapickle:BAAALgAECgMJAwAAAA==.Imbrium:BAAALgAECgUJCgABLgAECgYJFgADAOYhAA==.',
In='Invoked:BAABLgAECn8UAAQhAAcJMhPaGQC+AQAhAAcJMhPaGQC+AQAGAAMJ+RovQADmAAAlAAMJjQaPMgCBAAAAAA==.',
Io='Iorie:BAAALgAECgYJDQAAAA==.',
Ip='Iphei:BAABLgAECn8hAAIHAAgJOxMhDwCyAQAHAAgJOxMhDwCyAQAAAA==.',
Ir='Iroko:BAAALgAECgEJAQAAAA==.Irulanni:BAABLgAECn8gAAIBAAgJRxWsGQDHAQABAAgJRxWsGQDHAQAAAA==.',
Is='Iseeyoubaby:BAAALgADCgIJAgAAAA==.Istariya:BAAALgADCgcJEwAAAA==.',
It='Ithoria:BAAALgADCgEJAQABLgAECgYJBwAKAAAAAA==.Itwillkeel:BAAALgADCgcJEgAAAA==.',
Iv='Iva:BAABLgAECn8VAAICAAgJKSFkDABlAgACAAgJKSFkDABlAgAAAA==.',
Ja='Jagerhunter:BAAALgADCgMJAwABLgADCggJCAAKAAAAAA==.Jagershaii:BAAALgAECgUJBwAAAA==.Jagruid:BAAALgADCggJCAAAAA==.Jalaven:BAABLgAECn8bAAIgAAcJBgu9DAA3AQAgAAcJBgu9DAA3AQAAAA==.Jamelanister:BAAALgAECgEJAQAAAA==.Jasar:BAAALgADCgYJBgAAAA==.Jayani:BAAALgADCgQJBwAAAA==.',
Je='Jesaryth:BAAALgAECgEJAgAAAA==.Jessicka:BAAALgAECgUJEAAAAA==.Jesûs:BAAALgAECgEJAQAAAA==.Jethan:BAAALgAECgUJCQAAAA==.',
Jh='Jhalse:BAAALgADCgYJCgAAAA==.',
Ji='Jilley:BAAALgADCgQJBAAAAA==.Jinian:BAAALgADCgkJIQAAAA==.Jinyla:BAAALgAECgMJBAAAAA==.Jinz:BAAALgAECgYJDwAAAA==.',
Jo='Johchi:BAAALgADCgcJBwAAAA==.Johraco:BAABLgAECn8hAAMGAAcJXBoBEgB4AQAGAAcJXBoBEgB4AQAhAAEJwgHuJQAdAAABLgADCgcJBwAKAAAAAA==.Joust:BAAALgADCgUJCQAAAA==.',
Ju='Juke:BAAALgAECgYJEQABLgAECgkJLQABABghAA==.Justyra:BAAALgADCgkJCwAAAA==.Juve:BAABLgAECn8aAAMHAAcJCxcWEgCLAQAHAAcJNBQWEgCLAQAYAAYJIRG1GAAkAQAAAA==.Juyani:BAAALgAECgQJCQAAAA==.',
Ka='Ka:BAAALgADCgUJCAAAAA==.Kaeldon:BAAALgAECgQJBQAAAA==.Kaelenor:BAAALgADCgMJAwAAAA==.Kahma:BAAALgADCgYJBgAAAA==.Kailyn:BAAALgADCgcJBwAAAA==.Kaitia:BAAALgADCgkJEAAAAA==.Kaiyah:BAAALgAECgIJAwAAAA==.Kanab:BAAALgAECgUJCgAAAA==.Karazhak:BAAALgADCgEJAQAAAA==.Kasim:BAAALgAECgYJEgAAAA==.Kato:BAAALgADCgkJEAAAAA==.Kaygome:BAAALgAECgcJEwAAAA==.Kayllea:BAAALgADCgkJGgAAAA==.Kaysue:BAAALgADCgkJCQAAAA==.Kaytara:BAAALgAECgMJBAAAAA==.',
Ke='Keharn:BAAALgADCgcJEAAAAA==.Kelaros:BAAALgADCgUJCAAAAA==.Kelaroz:BAAALgAECgMJBAAAAA==.Kettock:BAAALgAECgQJCwAAAA==.',
Kh='Khronis:BAAALgADCgIJAwAAAA==.',
Ki='Kilj:BAABLgAECn8kAAIRAAgJGB4zDgA5AgARAAgJGB4zDgA5AgAAAA==.Kirsh:BAAALgADCgUJBQAAAA==.Kitherry:BAAALgAECgYJEwAAAA==.',
Kl='Klebsiella:BAAALgADCgMJBAAAAA==.',
Kn='Knomllik:BAABLgAECn8rAAMeAAgJrSXVAQBjAgAeAAgJrSXVAQBjAgACAAYJ5B08bwCqAQAAAA==.',
Ko='Koristil:BAAALgADCgYJCwAAAA==.Korrick:BAAALgADCggJEAAAAA==.Kowdrak:BAABLgAECn8XAAMGAAgJdAVwJADjAAAGAAcJBQVwJADjAAAhAAYJoAaSNgC3AAAAAA==.Kowdrek:BAAALgADCgkJEAAAAA==.Kowmann:BAAALgADCgkJFQAAAA==.',
Kr='Kreapen:BAAALgAECgUJEwAAAA==.Krisdk:BAACLgAFFH8IAAICAAMJKhIsPADfAAACAAMJKhIsPADfAAAuAAQKfyYAAx4ACAmvI0oDACECAAIACAnWIdAeAMgCAB4ACAl3IEoDACECAAAA.Krystil:BAAALgAECgcJCwAAAA==.',
Kt='Ktosh:BAAALgADCgcJBwAAAA==.',
Ku='Kurenäi:BAAALgAECggJDgAAAA==.Kurzul:BAAALgADCgEJAQAAAA==.',
Kw='Kwerin:BAAALgAECgUJCgAAAA==.',
Ky='Kyndrassa:BAAALgADCgIJAwAAAA==.Kynlari:BAAALgADCgEJAQAAAA==.Kypalgos:BAAALgAECgMJAwAAAA==.',
['Kí']='Kírî:BAAALgAECgQJBwAAAA==.',
['Kú']='Kúma:BAABLgAECn8kAAMaAAgJ5yGVBQCHAgAaAAgJ5yGVBQCHAgAVAAEJSAvgLwAiAAAAAA==.',
La='Lachichi:BAAALgADCgcJEwAAAA==.Laquiche:BAAALgADCgEJAQAAAA==.Larat:BAAALgADCgMJBgAAAA==.Larrysmith:BAAALgADCgEJAQAAAA==.Lazrael:BAAALgAECgQJBAAAAA==.',
Le='Leathe:BAAALgADCgMJAgAAAA==.Ledana:BAAALgAECgQJBgAAAA==.Legolamb:BAABLgAECn8aAAImAAcJABR7BQCKAQAmAAcJABR7BQCKAQAAAA==.Leicht:BAAALgAECgQJCAAAAA==.Leitch:BAAALgAECgYJDwAAAA==.Leviasaint:BAABLgAECn8dAAIHAAcJ3g/xNQBlAQAHAAcJ3g/xNQBlAQAAAA==.',
Li='Lifeinsuranc:BAAALgADCgcJBwAAAA==.Lightstim:BAAALgAECgQJBwAAAA==.Lilbolt:BAAALgAECgEJAQAAAA==.Lilseven:BAAALgADCgEJAQAAAA==.Liorah:BAAALgAECgQJBwAAAA==.Liptan:BAABLgAECn8dAAIcAAgJ2g0UGQCDAQAcAAgJ2g0UGQCDAQAAAA==.',
Lo='Lodtuspuch:BAAALgADCgMJAwAAAA==.Lohha:BAAALgAECgEJAQAAAA==.Lonesnipa:BAAALgADCgkJKgAAAA==.Looseyjoosey:BAAALgADCgkJKQABLgAECggJJAAnAEQXAA==.Lorealee:BAAALgAECgEJAQAAAA==.Lotharious:BAAALgADCgcJBwAAAA==.Louiswu:BAAALgAECgcJEgAAAA==.Loursten:BAAALgADCgYJCwAAAA==.',
Lu='Luckyzounds:BAABLgAECn8VAAIHAAYJvgRYKAC6AAAHAAYJvgRYKAC6AAAAAA==.Lunariya:BAAALgAECgUJCQAAAA==.Lunâire:BAAALgADCgUJBQAAAA==.',
Ly='Lycandra:BAAALgAECgMJAwAAAA==.Lyroll:BAAALgAECgYJEgAAAA==.Lyssa:BAAALgAECgEJAQAAAA==.Lyz:BAAALgAECgQJDAAAAA==.',
['Lû']='Lûcca:BAAALgAECgQJBAAAAA==.',
Ma='Maahthu:BAAALgAECgYJBgAAAA==.Maddogtannen:BAAALgADCgEJAQAAAA==.Maddrezus:BAAALgADCgkJCQAAAA==.Madreezus:BAABLgAECn8aAAILAAgJnyAQBgBVAgALAAgJnyAQBgBVAgAAAA==.Maelinaria:BAAALgADCgEJAQAAAA==.Magdalayna:BAAALgADCgkJEgAAAA==.Magique:BAAALgADCgcJDQAAAA==.Mai:BAAALgAECgIJBQAAAA==.Makarov:BAABLgAECn8VAAMZAAgJAyQrBwB7AgAZAAcJfCUrBwB7AgATAAEJsBnYVwBMAAAAAA==.Maladelyia:BAAALgADCgIJAgAAAA==.Mangodemon:BAACLgAFFH8PAAIaAAYJfRndCACaAQAaAAYJfRndCACaAQAuAAQKfyAAAxoACQlOIkYKADMDABoACQkKIUYKADMDABUAAgmpIHEbALUAAAAA.Mangopally:BAAALgAECgYJBwABLgAFFAYJDwAaAH0ZAA==.Mangoshammy:BAAALgAECgQJBQABLgAFFAYJDwAaAH0ZAA==.Mani:BAAALgAECgYJEgAAAA==.Mariaus:BAAALgAECgQJBgAAAA==.Marifernanda:BAAALgAECgQJCwAAAA==.Matteo:BAAALgADCgQJBAAAAA==.Mayuki:BAACLgAFFH8JAAISAAMJmxxJAwD7AAASAAMJmxxJAwD7AAAuAAQKfycAAhIACAkWJVwAAOcCABIACAkWJVwAAOcCAAAA.',
Mc='Mcboopies:BAAALgAECgEJAQAAAA==.Mckayle:BAABLgAECn8kAAMYAAgJqh42CgCWAgAYAAgJqh42CgCWAgAHAAcJLxs3IgDSAQAAAA==.Mckaylá:BAAALgAECgYJDAAAAA==.',
Me='Medorana:BAAALgAECgMJBAAAAA==.Mellxo:BAAALgAECgYJEQAAAA==.Meree:BAAALgADCgYJBgAAAA==.Meridion:BAAALgADCgEJAQAAAA==.Mewtilation:BAAALgAECgEJAgAAAA==.',
Mi='Midknieght:BAAALgADCgEJAQAAAA==.Midnis:BAAALgADCgQJBAAAAA==.Minalthor:BAAALgADCgYJBgAAAA==.Minthe:BAAALgAECgQJCAABLgAECgkJLQABABghAA==.Mirob:BAAALgAECgMJAwAAAA==.Mirrari:BAAALgAECgYJEwAAAA==.Mistrnimbus:BAAALgADCgIJAgAAAA==.',
Mo='Mockrage:BAAALgAECgIJAgAAAA==.Mohim:BAAALgADCggJDgAAAA==.Mojoshi:BAAALgADCgIJAgAAAA==.Molten:BAAALgAECgYJEwAAAA==.Monkdeeznuts:BAAALgAECgMJAwAAAA==.Moonsault:BAAALgAECgYJBgAAAA==.Mooreland:BAAALgADCgcJCgAAAA==.Morado:BAAALgADCgkJCgAAAA==.Morganite:BAAALgADCgcJBwAAAA==.Morgomir:BAAALgAECgEJAQAAAA==.Moronica:BAAALgAECgMJAwAAAA==.Morsviridi:BAAALgADCgIJAgAAAA==.Mox:BAAALgADCgcJBwAAAA==.',
Ms='Mscabalistic:BAAALgADCgIJAgAAAA==.',
Mu='Murdrmittens:BAABLgAECn8VAAIWAAcJVhb7EQBkAQAWAAcJVhb7EQBkAQAAAA==.Muyaa:BAAALgAECgQJBAAAAA==.',
My='Myrabeth:BAAALgAECgIJAgAAAA==.Mytternàkt:BAAALgAECgYJEgAAAA==.',
Na='Naldon:BAAALgAECgYJEgAAAA==.Naptimegames:BAAALgAECgUJBQAAAA==.Nararis:BAAALgADCgIJAgAAAA==.Nasmin:BAAALgAECgQJBgAAAA==.',
Ne='Nechta:BAAALgADCgMJBAAAAA==.Nemesyr:BAAALgAECgkJEgAAAA==.Nephtyys:BAAALgAECgYJEgAAAA==.Nerfbat:BAAALgAECgUJEwAAAA==.Nerus:BAAALgADCggJCAAAAA==.Nes:BAABLgAECn8aAAMVAAcJiA1bCQAPAQAVAAcJSQxbCQAPAQAfAAQJ6Ar1SQDKAAAAAA==.Nesaja:BAAALgADCgMJAwAAAA==.Netra:BAAALgADCgcJBwAAAA==.Neîth:BAAALgADCgkJKAAAAA==.',
Ni='Niavy:BAABLgAECn8aAAMTAAcJICIgCABpAgATAAcJICIgCABpAgAUAAEJ1A07UQAyAAAAAA==.Nicore:BAABLgAECn8UAAIfAAgJRBIxIgCrAQAfAAgJRBIxIgCrAQAAAA==.Nicorre:BAAALgADCggJCAAAAA==.Nightgecko:BAABLgAECn8fAAIPAAgJaCKdAgAfAgAPAAgJaCKdAgAfAgAAAA==.Nihaludan:BAAALgADCgUJBQAAAA==.Nikkiwood:BAAALgADCgUJBQAAAA==.Nineteen:BAAALgAECgcJCAABLgAFFAYJEgAXACcgAA==.',
No='Noanuki:BAAALgADCgcJDwAAAA==.Nogdem:BAABLgAECn8cAAIQAAcJnRjmBwCXAQAQAAcJnRjmBwCXAQAAAA==.Nohkan:BAAALgAECgQJDgAAAA==.Nordthewise:BAAALgADCgMJBAAAAA==.Noshtsherloc:BAABLgAECn8bAAIhAAgJKxCyCQCBAQAhAAgJKxCyCQCBAQAAAA==.Notdos:BAABLgAECn8VAAIGAAYJzQdaLAC3AAAGAAYJzQdaLAC3AAAAAA==.Nothebest:BAAALgADCgMJAwAAAA==.Novanafel:BAAALgADCgUJBQAAAA==.Novaprime:BAAALgAECgQJBwAAAA==.Novastra:BAAALgAECgcJCwAAAA==.Noweijose:BAAALgADCgYJBgABLgAECgYJFgADAOYhAA==.',
Ny='Nyxuraldusk:BAAALgADCgcJCwAAAA==.',
['Nù']='Nùrse:BAAALgAECgMJAwAAAA==.',
Ob='Oballa:BAAALgADCgQJBAAAAA==.Obeel:BAABLgAECn8hAAMoAAYJfA4ZDAAcAQAoAAYJhQwZDAAcAQASAAIJZRCqKABaAAAAAA==.',
Og='Oggers:BAAALgAECgUJCwAAAA==.',
Ot='Otosan:BAABLgAECn8mAAITAAgJYxCONgCpAQATAAgJYxCONgCpAQAAAA==.',
Ou='Outsiders:BAAALgADCgYJBgAAAA==.',
Pa='Paisàn:BAAALgAECgYJCQAAAA==.Paku:BAAALgADCgMJAwAAAA==.Pawsatyou:BAAALgAECgQJBQAAAA==.',
Pe='Peachiekeen:BAAALgAECgIJBAAAAA==.Peekãboo:BAACLgAFFH8IAAIdAAMJEh+2CwAfAQAdAAMJEh+2CwAfAQAuAAQKfysAAh0ACAnuJFkBAN4CAB0ACAnuJFkBAN4CAAAA.Peewheewoo:BAAALgADCgkJMAAAAA==.Penguin:BAAALgAECgQJCwAAAA==.Pepae:BAABLgAECn8rAAMDAAkJGCR8FAAuAwADAAkJGCR8FAAuAwAjAAIJmw9rFgBnAAAAAA==.',
Ph='Phantom:BAAALgAECgMJBQAAAA==.Pholia:BAAALgAECgQJCQAAAA==.',
Pi='Pieni:BAAALgAECgEJAQAAAA==.Pinkrose:BAAALgAECgYJEwAAAA==.Piñacolada:BAAALgADCgUJBQAAAA==.',
Pl='Platomatrixx:BAAALgAECgMJBgAAAA==.',
Po='Popnloc:BAAALgAECgIJAgAAAA==.',
Pr='Prayful:BAAALgAECgQJBAABLgAECgcJEwAKAAAAAA==.Priestsrsly:BAABLgAECn8aAAQYAAYJGSLuDwBAAgAYAAYJGSLuDwBAAgAHAAUJ8g/bSQARAQAIAAEJwQ00ZAAwAAAAAA==.',
Ps='Psyop:BAAALgAECgMJBAAAAA==.',
Pu='Pullmytail:BAABLgAECn8iAAQZAAgJfiHdBADDAgAZAAgJfiHdBADDAgAUAAQJgxOSUgD8AAATAAMJeBCAdQC6AAAAAA==.Punish:BAAALgAECgIJAwAAAA==.Purrsian:BAAALgADCgYJEAAAAA==.',
['På']='Påntuflaz:BAAALgAECgcJBgAAAA==.',
Qb='Qberks:BAABLgAECn8dAAICAAgJIh6THwDEAgACAAgJIh6THwDEAgAAAA==.',
Qe='Qelizari:BAAALgAECgEJAQAAAA==.',
Qu='Queliel:BAAALgAECgUJBQAAAA==.',
Qw='Qwelsha:BAAALgAECgEJAQAAAA==.',
Ra='Radtiz:BAAALgADCgUJCQAAAA==.Raenin:BAABLgAECn8UAAIMAAYJuRmoLgCPAQAMAAYJuRmoLgCPAQAAAA==.Ragingdraem:BAAALgAECgEJBAAAAA==.Raidei:BAABLgAECn8UAAMdAAUJURdEFgAnAQAdAAUJURdEFgAnAQAnAAEJBRHjHwAzAAAAAA==.Raimbish:BAAALgAECgEJAQAAAA==.Rainwater:BAAALgADCgUJBQAAAA==.Rajah:BAAALgADCggJDQAAAA==.Rakeripwait:BAABLgAECn8cAAMMAAcJxxuZCwDVAQAMAAcJehqZCwDVAQAoAAYJexhbEACnAQAAAA==.Raon:BAAALgADCgYJBgAAAA==.Ratatosk:BAABLgAECn8eAAIfAAgJmwX5EgAXAQAfAAgJmwX5EgAXAQAAAA==.Ratchef:BAAALgAECgMJCgAAAA==.Raventempus:BAABLgAECn8gAAIDAAgJ3RQNLAC0AQADAAgJ3RQNLAC0AQAAAA==.Rawheadrexx:BAAALgAECgEJAwAAAA==.',
Re='Rearden:BAAALgADCgYJBgAAAA==.Redatfirst:BAAALgADCgcJDQAAAA==.Redpawedfox:BAABLgAECn8jAAIEAAgJTxobDQA4AgAEAAgJTxobDQA4AgAAAA==.Rekviem:BAAALgAECgYJEAAAAQ==.Relifus:BAABLgAECn8VAAIOAAgJMSHuIQDyAQAOAAgJMSHuIQDyAQAAAA==.Renshin:BAAALgADCgYJBgAAAA==.Reshu:BAAALgADCgYJBgAAAA==.Resteel:BAAALgAECgEJAgAAAA==.Retallica:BAABLgAECn8aAAINAAcJ4ATzswAcAQANAAcJ4ATzswAcAQAAAA==.Revanite:BAABLgAECn8WAAIRAAYJmBdmfwBcAQARAAYJmBdmfwBcAQAAAA==.Rexy:BAAALgADCgcJCAAAAA==.Rexydh:BAAALgADCgYJCwAAAA==.Rexygos:BAAALgAECgUJCgAAAA==.',
Rh='Rhavaniel:BAAALgAECgUJDQAAAA==.',
Ri='Rikola:BAAALgAECgEJAQAAAA==.Rimamoo:BAAALgADCgcJCAAAAA==.Rizay:BAAALgADCgYJBgAAAA==.',
Ro='Roderika:BAAALgAECgUJBgAAAA==.Rorak:BAAALgADCggJCAAAAA==.Royalnewb:BAAALgAECgcJEQABLgAECggJHwAUADQYAA==.Royston:BAABLgAECn8jAAIiAAgJIQ5dDABdAQAiAAgJIQ5dDABdAQAAAA==.',
Ru='Rucereal:BAAALgAECgYJDwAAAA==.Ruie:BAAALgADCgMJAwAAAA==.Runefire:BAAALgAECgQJBgAAAA==.Ruperd:BAABLgAECn8eAAINAAcJ2BuBHgDSAQANAAcJ2BuBHgDSAQAAAA==.Rushzen:BAAALgADCggJDQAAAA==.Russell:BAAALgAECgMJAwAAAA==.Rustyaf:BAAALgADCgYJCgAAAA==.',
Ry='Rynsidious:BAABLgAECn8jAAIfAAcJMRpJCwCIAQAfAAcJMRpJCwCIAQAAAA==.',
['Rã']='Rãin:BAAALgAECgMJBQABLgAECggJHwAMAPsVAA==.',
Sa='Sabelle:BAAALgAECgYJEwAAAA==.Saebel:BAAALgAECgcJCQAAAA==.Saeton:BAABLgAECn8aAAIQAAgJnQvIDQAjAQAQAAgJnQvIDQAjAQAAAA==.Sahlaris:BAAALgAECgYJDwAAAA==.Saladfingrs:BAACLgAFFH8MAAMEAAQJ+huADABBAQAEAAQJ+huADABBAQAMAAEJ/A3uHgBLAAAuAAQKfyQAAgQACAnfIdMPALoCAAQACAnfIdMPALoCAAAA.Saladin:BAAALgADCgcJCwAAAA==.Salno:BAAALgAECgQJBAAAAA==.Salvora:BAAALgADCgMJAwAAAA==.Samsonite:BAAALgAECgYJCwAAAA==.Sargerik:BAAALgADCgMJAwAAAA==.Savreen:BAAALgADCgUJBQAAAA==.',
Sc='Scrubdh:BAACLgAFFH8JAAIaAAQJCiBdCwB8AQAaAAQJCiBdCwB8AQAuAAQKfxoAAxoACAkfI4EOAAsDABoACAkfI4EOAAsDAB8AAQleEfJuADYAAAAA.',
Se='Sekhet:BAABLgAECn8kAAMHAAgJXBl0CgAAAgAHAAcJkxt0CgAAAgAIAAgJ2BMmCwDNAQAAAA==.Sekstrasza:BAAALgADCgkJIQAAAA==.Selenika:BAAALgADCgIJAgAAAA==.Serethyne:BAAALgADCgQJBwAAAA==.Serrahunt:BAAALgAECgQJBAAAAA==.Severia:BAAALgADCgQJBAAAAA==.',
Sh='Shacakes:BAAALgAECgYJDQAAAA==.Shamanoid:BAAALgAECgYJBgABLgAECgcJDgAKAAAAAA==.Shasta:BAABLgAECn8iAAINAAgJUh5gEgAnAgANAAgJUh5gEgAnAgAAAA==.Shear:BAAALgADCgIJAgABLgAECgcJCwAKAAAAAA==.Shekelshaker:BAABLgAECn8kAAInAAgJRBeEAgD3AQAnAAgJRBeEAgD3AQAAAA==.Shinymetat:BAAALgAECgEJAQAAAA==.Shozmonk:BAAALgAECgQJBQAAAA==.',
Si='Siik:BAAALgAECgEJAQABLgAECgUJCgAKAAAAAA==.Silaena:BAAALgAECgUJEwAAAA==.Silverlocke:BAABLgAECn8UAAIQAAcJzBDWHwAJAQAQAAcJzBDWHwAJAQAAAA==.Sinstergates:BAAALgAECgcJEQAAAA==.Sinvyr:BAAALgAECgYJDQABLgAECggJGQAaAGYVAA==.Sinvyris:BAABLgAECn8ZAAIaAAgJZhX3NQAfAgAaAAgJZhX3NQAfAgAAAA==.',
Sk='Skagirl:BAAALgAECgUJCwAAAA==.Skillscales:BAACLgAFFH8KAAMGAAMJiQ+MFwDsAAAGAAMJiQ+MFwDsAAAlAAEJagblCgBOAAAuAAQKfzEAAwYACAkWJEgCANcCAAYACAlYI0gCANcCACUACAkCG9UEALYCAAAA.Skor:BAAALgAECgcJDAAAAA==.Skyblaze:BAAALgAECgkJBAAAAA==.Skyfallen:BAAALgAECgcJEwAAAA==.',
Sl='Sleepeh:BAAALgADCgUJBQAAAA==.Slimjim:BAAALgAECgIJAgABLgAECgYJFgADAOYhAA==.Slink:BAAALgADCgIJAgAAAA==.Slovik:BAAALgAECgcJEAAAAA==.',
Sm='Smarb:BAAALgAECgEJAQABLgAECgUJEAAKAAAAAA==.Smooth:BAAALgAECgYJCgAAAA==.',
So='Solanar:BAAALgADCgIJAgAAAA==.Solanea:BAAALgAECgYJEwAAAA==.Sonic:BAAALgAECgIJBAAAAA==.Sorcforce:BAAALgADCgMJAwAAAA==.Sorin:BAAALgADCgkJHAABLgAECggJJAARABgeAA==.Soultelage:BAAALgAECgMJAwAAAA==.Soupwiz:BAAALgAECgEJAQAAAA==.Sourwine:BAAALgAECgQJCgAAAA==.',
Sp='Sparklecakes:BAAALgAECgcJBwAAAA==.Spritedk:BAAALgAECgUJEQAAAA==.Spritemonk:BAAALgAECgcJDwAAAA==.Spritepally:BAABLgAECn8kAAMFAAcJ7xxFGABQAgAFAAcJ7xxFGABQAgAQAAYJzRRpDQApAQAAAA==.',
St='Stalk:BAAALgAECgQJBwAAAA==.Starlørd:BAABLgAECn8cAAMMAAcJhhBUFwBFAQAMAAcJhhBUFwBFAQAEAAIJ7wZ/ugBRAAAAAA==.Stavilde:BAAALgAECgEJAgAAAA==.Stemavesa:BAAALgADCgkJFwABLgAECggJIgANAFIeAA==.Stichy:BAAALgAECgQJBAABLgAECggJHwAMAPsVAA==.Stormdancer:BAABLgAECn8fAAIZAAgJEiLsAgAOAwAZAAgJEiLsAgAOAwAAAA==.Stormtusk:BAAALgADCgYJBwAAAA==.Strangiatie:BAAALgADCgcJCgAAAA==.Stumpyfoot:BAABLgAECn8VAAIEAAgJERf6RQCKAQAEAAgJERf6RQCKAQAAAA==.Stygi:BAAALgADCgQJBAAAAA==.Stãrs:BAACLgAFFH8KAAIMAAMJrhftDwD9AAAMAAMJrhftDwD9AAAuAAQKfzAAAgwACAlaJOABAOgCAAwACAlaJOABAOgCAAAA.',
Su='Sugarmama:BAAALgAECgMJBQAAAA==.Sunstrap:BAAALgAECgEJAQAAAA==.Sunwarden:BAAALgAECgMJAwAAAA==.',
Sv='Svx:BAAALgADCgcJCAAAAA==.',
Sw='Switchcase:BAABLgAECn8fAAIEAAgJsB/iCgBaAgAEAAgJsB/iCgBaAgAAAA==.',
Sy='Sylviria:BAAALgADCgEJAQAAAA==.Syntharia:BAABLgAECn8pAAIGAAkJuQr6EACFAQAGAAkJuQr6EACFAQAAAA==.Syyiasia:BAAALgADCgcJBwAAAA==.',
Sz='Szintra:BAAALgAECgQJBwAAAA==.',
['Sê']='Sêrenn:BAAALgADCgIJAgAAAA==.',
['Së']='Sërpentine:BAAALgAECgIJAgABLgAECggJHwAMAPsVAA==.',
Ta='Taffigosa:BAABLgAECn8kAAIGAAgJ/RrbBwATAgAGAAgJ/RrbBwATAgAAAA==.Taffy:BAAALgADCgYJBwAAAA==.Takodaddy:BAAALgADCgUJBQAAAA==.Taledol:BAAALgADCgcJCQAAAA==.Tanaelyn:BAAALgADCgEJAQAAAA==.Tanthel:BAABLgAECn8gAAIWAAgJ3xAjEAB7AQAWAAgJ3xAjEAB7AQAAAA==.Taroboba:BAAALgAECgYJBQAAAA==.Taursain:BAAALgAECgEJAQAAAA==.',
Tb='Tbh:BAAALgAECgcJEQAAAA==.',
Te='Telemacon:BAAALgADCgIJAgABLgADCggJCAAKAAAAAA==.Temple:BAAALgAECgQJBAAAAA==.Tental:BAAALgADCgcJCwAAAA==.Terraquis:BAAALgAECgcJEAAAAA==.Testarossa:BAAALgAECgIJAwABLgAECggJFQAZAAMkAA==.',
Th='Thalyon:BAAALgAECgcJBQAAAA==.Thekillagirl:BAAALgAECgQJCQAAAA==.Thiccbiddies:BAABLgAECn8mAAILAAgJOhgyCgAHAgALAAgJOhgyCgAHAgAAAA==.Thompson:BAAALgADCggJEwAAAA==.Thorad:BAAALgADCgMJAwAAAA==.Thordrann:BAAALgADCgEJAQAAAA==.Thorgyllan:BAABLgAECn8WAAINAAgJRBvjKACBAgANAAgJRBvjKACBAgAAAA==.Thort:BAAALgAECgYJDAAAAA==.Thunderwings:BAAALgAECgMJAwAAAA==.',
Ti='Tiaramisu:BAABLgAECn8UAAIWAAgJTxLvHAD0AQAWAAgJTxLvHAD0AQAAAA==.Tienmu:BAABLgAECn8VAAITAAcJNiS7BACxAgATAAcJNiS7BACxAgABLgADCgkJEAAKAAAAAA==.Tigan:BAABLgAECn8TAAMaAAcJnRALLAA0AQAaAAcJnRALLAA0AQAVAAEJqw4bMQAeAAAAAA==.Tigerlily:BAAALgAECgEJAgAAAA==.Tigra:BAABLgAECn8ZAAIMAAgJVxDPEgBzAQAMAAgJVxDPEgBzAQAAAA==.Timeweaver:BAABLgAECn8fAAMhAAgJRQ+OCACeAQAhAAgJRQ+OCACeAQAlAAEJywhIQAAwAAAAAA==.Tirank:BAAALgADCgUJBwAAAA==.Tirmone:BAABLgAECn8VAAMXAAcJUhcSDwC2AQAXAAYJaBkSDwC2AQAWAAEJCBKRQgA/AAAAAA==.',
To='Toastshark:BAABLgAECn8VAAIDAAgJHB5ebAD8AQADAAgJHB5ebAD8AQAAAA==.Toirneach:BAAALgADCgIJAgABLgAECgQJBQAKAAAAAA==.Toranaar:BAAALgADCgkJCQAAAA==.Torapaw:BAAALgADCgkJIgAAAA==.Totorö:BAABLgAECn8fAAIMAAgJ+xVxIQDxAQAMAAgJ+xVxIQDxAQAAAA==.',
Tr='Trayfu:BAAALgAECgYJEwAAAA==.Trice:BAAALgADCgkJGgAAAA==.Trollie:BAAALgADCgEJAQAAAA==.Trostani:BAAALgADCgcJCgAAAA==.Truetotem:BAAALgAECgcJEAAAAA==.Trusker:BAABLgAECn8eAAInAAcJKBiXAwCwAQAnAAcJKBiXAwCwAQAAAA==.Trypticon:BAAALgADCgYJBgAAAA==.Tryst:BAAALgAECgIJAgAAAA==.',
Tu='Tullir:BAAALgADCgcJBwAAAA==.Tuo:BAAALgADCgIJAgAAAA==.Turniphead:BAAALgAECgYJEQAAAA==.',
Tw='Twitty:BAABLgAECn8gAAIXAAkJKh+VAQAmAwAXAAkJKh+VAQAmAwAAAA==.',
Ty='Tyravana:BAAALgADCgIJAgAAAA==.Tystriel:BAAALgAECgcJEwAAAA==.',
Ul='Ulasar:BAAALgAECgQJBQAAAA==.',
Un='Unknownn:BAAALgADCgcJCAAAAA==.Unrak:BAABLgAECn8ZAAINAAcJihDKdQCPAQANAAcJihDKdQCPAQAAAA==.Untarot:BAAALgAECgIJAwAAAA==.',
Up='Uptyhme:BAAALgADCgMJAwAAAA==.',
Ur='Urmaker:BAAALgAECgEJAQAAAA==.',
Ut='Utinni:BAAALgAECgYJDQAAAA==.',
Va='Vaitlynn:BAAALgAECgEJAQAAAA==.Valcia:BAAALgADCgcJCgAAAA==.Valdanyr:BAEALgAECgYJEwAAAA==.Valkarr:BAAALgADCgEJAQABLgAECgcJEQAKAAAAAA==.Valkyrîe:BAAALgAECgcJEQAAAA==.Valorfist:BAABLgAECn8bAAIFAAcJax4PFAByAgAFAAcJax4PFAByAgAAAA==.Vancleef:BAABLgAECn8VAAInAAgJTBQoCgCTAQAnAAgJTBQoCgCTAQAAAA==.Vandar:BAAALgAECgcJEwAAAA==.Varmav:BAABLgAECn8cAAIcAAgJQhSGDQDtAQAcAAgJQhSGDQDtAQAAAA==.Varsi:BAABLgAECn8gAAIBAAgJRxq3FADsAQABAAgJRxq3FADsAQAAAA==.Varân:BAABLgAECn8aAAIFAAcJNhsFDgD7AQAFAAcJNhsFDgD7AQAAAA==.Vask:BAAALgAFFAIJAgAAAA==.',
Ve='Vede:BAAALgAECgYJEgAAAA==.Velash:BAABLgAECn8nAAMaAAcJaR1vGgCWAQAfAAYJXR03GQD8AQAaAAYJXhtvGgCWAQAAAA==.Velliria:BAABLgAECn8aAAIRAAcJ9hgkRgD5AQARAAcJ9hgkRgD5AQAAAA==.Velyandril:BAAALgAECgQJBwAAAA==.Vendorin:BAAALgAECgYJEwAAAA==.Vendre:BAABLgAECn8gAAMaAAgJxx56BwBjAgAaAAgJRB56BwBjAgAVAAEJkSNlJQBYAAAAAA==.Venilor:BAAALgAECgUJCQAAAA==.Veroswen:BAAALgADCggJCAAAAA==.Verratanectu:BAAALgAECgcJAwAAAA==.Verratanikto:BAAALgAECgYJEAAAAA==.Verwínd:BAAALgADCgMJBQAAAA==.Vett:BAAALgAECgMJBAAAAA==.',
Vi='Vický:BAAALgADCgIJAwAAAA==.Virusgt:BAAALgAECgcJDAAAAA==.Vita:BAAALgADCgkJGgAAAA==.Vitner:BAAALgADCgMJAwABLgAECgcJEQAKAAAAAA==.',
Vk='Vkandis:BAAALgAECgEJAQAAAA==.',
Vo='Voidbeam:BAAALgAECgEJAQAAAA==.Volker:BAAALgADCgEJAQAAAA==.Voltaris:BAAALgAECgMJAwAAAA==.',
Vr='Vriska:BAAALgADCgMJAwAAAA==.',
['Vâ']='Vânden:BAAALgAFFAIJAgAAAA==.',
Wa='Wakawaka:BAABLgAECn8mAAMYAAgJPB5fBACJAgAYAAgJPB5fBACJAgAHAAEJ0hfceQBBAAABLgAECgkJIAAXACofAA==.Waq:BAAALgAECgIJAgAAAA==.Washackedd:BAABLgAECn8aAAIHAAYJ2A8KGQBAAQAHAAYJ2A8KGQBAAQAAAA==.',
We='Wemad:BAAALgAECgYJDAAAAA==.',
Wi='Wife:BAABLgAECn8kAAMLAAgJiR0qCAAoAgALAAgJiR0qCAAoAgAiAAMJCAfUHwB+AAAAAA==.Wildfirê:BAAALgAECgYJBgABLgAFFAQJDQAJAI8jAA==.Winna:BAAALgADCgIJAgAAAA==.Witdh:BAAALgAECgYJCgAAAA==.',
Wo='Wolffy:BAAALgADCgQJBAAAAA==.Woop:BAABLgAECn8eAAIWAAcJqRvkCgDHAQAWAAcJqRvkCgDHAQAAAA==.Wormsloe:BAABLgAECn8XAAITAAcJaBWZFQC8AQATAAcJaBWZFQC8AQAAAA==.',
Wr='Wraîith:BAAALgADCgQJBAAAAA==.',
Xa='Xaida:BAABLgAECn8eAAIWAAcJUB59CgDOAQAWAAcJUB59CgDOAQAAAA==.Xaldania:BAAALgADCgkJGQAAAA==.',
Xe='Xeav:BAAALgADCgIJAgAAAA==.Xeev:BAAALgAECgEJAQAAAA==.',
Xu='Xuing:BAABLgAECn8gAAIXAAgJ6SQ0AQBHAwAXAAgJ6SQ0AQBHAwAAAA==.',
Ya='Yahweh:BAAALgADCgcJDgAAAA==.Yangtze:BAAALgAECgEJAQAAAA==.Yarro:BAABLgAECn8aAAIBAAcJfxR9OQDIAQABAAcJfxR9OQDIAQAAAA==.Yaxxa:BAAALgADCgEJAQAAAA==.',
Yo='Yorozu:BAAALgAECggJDgAAAA==.Youngblud:BAAALgAECgQJBQAAAA==.Yourrorstfea:BAAALgADCgUJBQAAAA==.',
Yv='Yvarca:BAAALgAECgIJAgABLgAECgYJCwAKAAAAAA==.',
Za='Zaela:BAABLgAECn8eAAIDAAcJ8xsZKgC8AQADAAcJ8xsZKgC8AQAAAA==.Zaku:BAAALgADCgcJDAAAAA==.Zamadi:BAAALgADCgcJEgAAAA==.Zax:BAAALgAECgYJDQAAAA==.',
Ze='Zendeth:BAABLgAECn8eAAMhAAgJ6CCTEAAyAgAhAAgJ6CCTEAAyAgAGAAEJLxTkXwA7AAAAAA==.Zerlin:BAAALgAECgMJAwAAAA==.Zeroximo:BAABLgAECn8WAAIDAAgJ7BchUwA+AgADAAgJ7BchUwA+AgAAAA==.',
Zi='Zipline:BAABLgAECn8dAAMaAAgJyRhkHACJAQAaAAcJFBlkHACJAQAfAAIJNw8KLABFAAAAAA==.',
Zm='Zmbie:BAAALgAECgEJAQABLgAECgYJEwAKAAAAAA==.',
Zo='Zombiexcat:BAAALgAECgYJEwAAAA==.Zoraell:BAABLgAECn8aAAICAAcJ/R1jIADFAQACAAcJ/R1jIADFAQAAAA==.Zordiak:BAAALgADCgEJAQAAAA==.Zordiakzero:BAABLgAECn8UAAIgAAcJ3hx1CwDqAQAgAAcJ3hx1CwDqAQAAAA==.Zoroaster:BAAALgADCgkJGQAAAA==.Zortaek:BAABLgAECn8iAAITAAkJrxpuFwBaAgATAAkJrxpuFwBaAgAAAA==.',
Zu='Zuki:BAABLgAECn8nAAMPAAcJtCL2GABgAgAPAAcJdCD2GABgAgABAAUJIyO1IACdAQAAAA==.',
Zw='Zweibellion:BAABLgAECn8eAAMGAAcJ7xU0DwCbAQAGAAcJ7xU0DwCbAQAhAAcJsQ92DgAZAQAAAA==.',
Zz='Zzhunger:BAAALgADCggJDwAAAA==.Zzlazzers:BAAALgAECgcJCAAAAA==.Zzyuniver:BAAALgADCgcJCQAAAA==.',
['Âr']='Ârês:BAAALgAECgEJAQAAAA==.',
['Äñ']='Äñûßîs:BAAALgADCggJCwAAAA==.',
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
