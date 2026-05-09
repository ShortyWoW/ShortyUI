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

local lookup = {'Hunter-BeastMastery','DeathKnight-Unholy','Mage-Frost','Warrior-Fury','Priest-Discipline','Priest-Holy','Druid-Restoration','Paladin-Holy','Evoker-Augmentation','Priest-Shadow','Hunter-Survival','Unknown-Unknown','Druid-Balance','Paladin-Retribution','Monk-Brewmaster','Hunter-Marksmanship','Paladin-Protection','Warlock-Destruction','Warlock-Demonology','Druid-Guardian','Shaman-Restoration','Shaman-Elemental','DemonHunter-Vengeance','Monk-Windwalker','Monk-Mistweaver','Mage-Arcane','Shaman-Enhancement','DemonHunter-Devourer','Warlock-Affliction','Rogue-Subtlety','DeathKnight-Blood','Evoker-Preservation','Rogue-Assassination','DemonHunter-Havoc','Mage-Fire','Warrior-Arms','Warrior-Protection','Evoker-Devastation','Rogue-Outlaw','Druid-Feral',}
local provider = {region='US',realm='Elune',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aanallein:BAAALgAECgEJAQAAAA==.',
Ae='Aeithir:BAAALgAECgEJAQAAAA==.Aerwin:BAAALgAECgEJBgAAAA==.Aesterid:BAAALgAECgEJAQAAAA==.Aethyr:BAAALgAECgYJCgAAAA==.',
Af='Afflictor:BAAALgAECgkJCwAAAA==.',
Ai='Aidivh:BAAALgAECgEJAQAAAA==.',
Ak='Akashah:BAABLgAECn8fAAIBAAgJYggoSQAyAQABAAgJYggoSQAyAQAAAA==.Akeno:BAABLgAECn8hAAICAAgJfR6kJADwAQACAAgJfR6kJADwAQAAAA==.Akhen:BAABLgAECn8gAAIDAAkJ/R0VEQCRAgADAAkJ/R0VEQCRAgAAAA==.',
Al='Alarick:BAABLgAECn8WAAIEAAYJ1x/4EwDMAQAEAAYJ1x/4EwDMAQAAAA==.Alatha:BAAALgAECgMJBAABLgAECgkJLAADAAYcAA==.Alathasedai:BAABLgAECn8sAAIDAAkJBhwDDwCkAgADAAkJBhwDDwCkAgAAAA==.Alathea:BAABLgAECn8VAAMFAAcJzRhoGABxAQAFAAcJBhhoGABxAQAGAAYJMg2YRAAnAQAAAA==.Alayil:BAAALgAECgUJDQAAAA==.Aledis:BAACLgAFFH8IAAICAAMJxx+BOgAiAQACAAMJxx+BOgAiAQAuAAQKfzEAAgIACQnaJAYDAD8DAAIACQnaJAYDAD8DAAAA.Alexaera:BAAALgADCgUJBQAAAA==.Algeni:BAAALgAECgEJAQAAAA==.Alichia:BAAALgAECgkJBwAAAA==.Alissa:BAAALgADCgMJAwAAAA==.Allanøn:BAAALgAECgYJDwAAAA==.Almuqit:BAABLgAECn8lAAIBAAcJJR85GAAOAgABAAcJJR85GAAOAgAAAA==.Alphaba:BAAALgADCgQJBwAAAA==.Alyrical:BAABLgAECn8WAAIHAAcJNxfeLwBhAQAHAAcJNxfeLwBhAQAAAA==.',
Am='Amalith:BAAALgAECgcJBwAAAA==.Amowrath:BAABLgAECn8kAAIIAAcJhhZ2FwDRAQAIAAcJhhZ2FwDRAQAAAA==.Amyasia:BAAALgAECgcJEwAAAA==.Amyxia:BAAALgAECgcJCQAAAA==.Amára:BAAALgAECgYJBwAAAA==.',
An='Anaaru:BAAALgADCgEJAgAAAA==.Andrai:BAAALgADCgMJAwAAAA==.Animax:BAAALgAECgEJAwAAAA==.Animethighs:BAAALgAECgUJCwAAAA==.Anitajones:BAAALgAECgIJBQAAAA==.Annaleth:BAAALgAECgcJCwAAAA==.Annieoakley:BAAALgADCgQJBAAAAA==.',
Ao='Aoski:BAAALgADCgYJBgABLgAECgYJGgAJAM4HAA==.',
Aq='Aquaskies:BAABLgAECn8XAAIJAAkJ2xkKBgCAAgAJAAkJ2xkKBgCAAgAAAA==.',
Ar='Aradoa:BAACLgAFFH8FAAIGAAMJuiRrCAA+AQAGAAMJuiRrCAA+AQAuAAQKfx0AAwYACAnvEKcrAJkBAAYACAnvEKcrAJkBAAoABglYEcEtAHEBAAAA.Arashin:BAAALgAECgYJDAAAAA==.Arawn:BAAALgADCgMJAwAAAA==.Arkanthul:BAAALgADCgUJBQAAAA==.Arkmonk:BAAALgAECgQJCQAAAA==.Arknight:BAABLgAECn8VAAILAAcJxhPUEwCHAQALAAcJxhPUEwCHAQAAAA==.Arlynn:BAAALgAECgMJAwAAAA==.Artemysia:BAAALgADCgkJCwAAAA==.Arturía:BAABLgAECn8bAAILAAgJVB6JAwDtAgALAAgJVB6JAwDtAgABLgAFFAEJAQAMAAAAAA==.Arylin:BAAALgAECgIJAgAAAA==.Arysa:BAAALgAECgIJAgAAAA==.',
As='Astartes:BAABLgAECn8VAAIEAAcJUB6zJwAfAgAEAAcJUB6zJwAfAgAAAA==.Astoria:BAABLgAECn8rAAINAAgJ5xKAJADZAQANAAgJ5xKAJADZAQAAAA==.Astreae:BAAALgAECgYJBwAAAA==.Astreri:BAAALgADCgcJCwABLgAECgYJCgAMAAAAAA==.',
At='Atamus:BAAALgAECgcJDAAAAA==.',
Au='Augmentation:BAAALgADCgYJBgAAAA==.Aundil:BAAALgADCgYJBgAAAA==.',
Av='Aveline:BAAALgAECgMJAwAAAA==.Avi:BAAALgAECgcJCgABLgAECgkJHgACAIQiAA==.Avoir:BAAALgADCgEJAQAAAA==.Avrathrael:BAAALgAECgEJAQAAAA==.',
Ax='Axos:BAABLgAECn8dAAIOAAgJlRTRLQDFAQAOAAgJlRTRLQDFAQAAAA==.Axxe:BAAALgADCgMJAwAAAA==.',
Ay='Aya:BAAALgAECggJEQAAAA==.Ayekillu:BAAALgAFFAEJAQAAAA==.Ayiasofia:BAABLgAECn8kAAIGAAgJcx8BEQBbAgAGAAgJcx8BEQBbAgAAAA==.Ayire:BAABLgAECn8dAAIBAAgJUBm2GAALAgABAAgJUBm2GAALAgAAAA==.Ayla:BAABLgAECn8lAAIPAAcJZwPRMQDTAAAPAAcJZwPRMQDTAAAAAA==.Aylan:BAABLgAECn8eAAIPAAgJIRViEADGAQAPAAgJIRViEADGAQABLgAECgcJDwAMAAAAAA==.Aylian:BAAALgADCgkJEgABLgAECgcJDwAMAAAAAA==.Ayumfox:BAABLgAECn8VAAQBAAgJCh32EgA5AgABAAgJChz2EgA5AgAQAAMJ4hVMGwBwAAALAAEJZQrDPQA8AAAAAA==.Ayumm:BAAALgAECgYJDwAAAA==.',
Az='Azapal:BAACLgAFFH8FAAIOAAMJlAdBNQDiAAAOAAMJlAdBNQDiAAAuAAQKfyAAAxEACAkLHKEHAGMCABEACAmvGqEHAGMCAA4ABwm7GHtsAKUBAAAA.Azarialilith:BAAALgADCgEJAQAAAA==.Aztez:BAAALgADCgMJAwAAAA==.Azuremagi:BAAALgAECgEJAgAAAA==.Azures:BAAALgADCgcJCAAAAA==.Azuros:BAAALgAECggJDwAAAA==.Azzorael:BAAALgAECgYJCQAAAA==.',
['Aë']='Aëmeath:BAABLgAECn8ZAAIKAAcJcB3OEQBtAgAKAAcJcB3OEQBtAgAAAA==.',
Ba='Babyjezuz:BAAALgAECgIJAgAAAA==.Badger:BAABLgAECn8lAAIEAAkJ3yG3AwDNAgAEAAkJ3yG3AwDNAgAAAA==.Balloon:BAAALgAECgYJBgAAAA==.Balthotros:BAAALgAECggJCQAAAA==.Bandâid:BAAALgADCgcJEwABLgAECgQJCQAMAAAAAA==.Barathiel:BAACLgAFFH8JAAIBAAMJkwlsLADlAAABAAMJkwlsLADlAAAuAAQKfzkAAgEACAlvHkoOAGcCAAEACAlvHkoOAGcCAAAA.Barlow:BAABLgAECn8VAAISAAYJUQx+EADUAAASAAYJUQx+EADUAAAAAA==.Baryll:BAABLgAECn8hAAIIAAgJZhEHGwCxAQAIAAgJZhEHGwCxAQAAAA==.Bathei:BAAALgADCgkJDwAAAA==.Battlebruver:BAAALgAECgUJDAAAAA==.',
Bc='Bc:BAEALgADCgcJBwABLgAECggJGAATAPgmAA==.',
Be='Beardude:BAAALgADCgIJAQAAAA==.Bearserkêr:BAAALgADCgYJBgAAAA==.Bellitrix:BAAALgADCgkJFwAAAA==.Bellne:BAAALgAECgUJCwAAAA==.',
Bi='Biefcake:BAABLgAECn8oAAICAAgJ+w11PgCCAQACAAgJ+w11PgCCAQAAAA==.Bigmoo:BAABLgAECn87AAIUAAkJghu5AgB/AgAUAAkJghu5AgB/AgAAAA==.Billnye:BAAALgADCgYJBgAAAA==.Bimbi:BAAALgADCgQJBAABLgAECgMJAwAMAAAAAA==.Biscoff:BAAALgAECgMJAwAAAA==.Bizmatec:BAAALgAECgUJBgAAAA==.',
Bl='Blackparade:BAAALgAECgYJEAAAAA==.Bladesong:BAAALgADCgMJAgAAAA==.Blaydon:BAAALgAECgYJDAABLgAECgcJDAAMAAAAAA==.Blayusa:BAAALgAECgcJDAAAAA==.Blended:BAAALgAECgIJAgAAAA==.Bloodancient:BAAALgADCgEJAwAAAA==.Blush:BAAALgAECgQJBAAAAA==.Blyzard:BAAALgADCgQJBAAAAA==.',
Bo='Boiledfrogz:BAABLgAECn8gAAMNAAkJdhe8EQC7AQANAAgJ3Ri8EQC7AQAHAAUJsBdXMABfAQAAAA==.Bolognese:BAAALgAECgUJCwAAAA==.Boned:BAACLgAFFH8NAAIBAAQJYSBkBwAsAQABAAQJYSBkBwAsAQAuAAQKfyoAAwEACQlrIh0BAKQDAAEACQlrIh0BAKQDABAAAgn1AH6BAEEAAAAA.Boopboops:BAABLgAECn8ZAAMVAAgJyhlyMQDBAQAVAAgJyhlyMQDBAQAWAAMJFRBvawCVAAAAAA==.Bootybreeze:BAAALgADCgEJAgAAAA==.Bottombear:BAAALgADCgYJCQAAAA==.',
Br='Bravehearthx:BAAALgAECgcJDgAAAA==.Breija:BAAALgAECgMJAwAAAA==.Bringerdk:BAAALgAECgQJEwAAAA==.Bringerlk:BAAALgAECgQJBAAAAA==.Bringerp:BAAALgAECgQJEwAAAA==.Brogend:BAAALgAECgYJDAABLgAECgkJJQAEAN8hAA==.Brohym:BAAALgAECgUJDAAAAA==.Brokki:BAAALgAECgIJBQAAAA==.Bronwyn:BAABLgAECn8VAAINAAYJ/g66LgDZAAANAAYJ/g66LgDZAAAAAA==.Brúh:BAAALgAECgMJBQABLgAECgYJEwAMAAAAAA==.',
Bu='Buffiey:BAAALgADCgcJHQAAAA==.Bugjug:BAAALgADCgIJAQAAAA==.Butterdish:BAAALgAECgEJAQABLgAECgkJFgAXAJMNAA==.',
Bz='Bz:BAAALgADCgIJAgAAAA==.',
Ca='Caféconron:BAAALgAECgEJAgAAAA==.Caitsidhe:BAABLgAECn8VAAIUAAcJnAYMIACfAAAUAAcJnAYMIACfAAAAAA==.Cannan:BAAALgAECgEJAwAAAA==.Cannute:BAAALgAECgYJEQAAAA==.Canuckdemon:BAAALgADCgEJAQAAAA==.Canuckdruid:BAAALgADCgUJBQAAAA==.Canuckranger:BAAALgAECgIJBAAAAA==.Canucksham:BAAALgADCggJCAAAAA==.Captnubcakes:BAABLgAECn8ZAAIEAAcJOSARFQDBAQAEAAcJOSARFQDBAQABLgAECggJCQAMAAAAAA==.Capziestrian:BAABLgAECn8pAAQPAAgJZBxkCgAdAgAPAAgJZBxkCgAdAgAYAAMJqBLkUgDGAAAZAAIJthQeVgB3AAAAAA==.Carathir:BAAALgAECgIJAQABLgAFFAYJGQAYAModAA==.Carefreè:BAACLgAFFH8ZAAIYAAYJyh3qAADpAQAYAAYJyh3qAADpAQAuAAQKfyQAAhgACQk1JBcBALcDABgACQk1JBcBALcDAAAA.Castallia:BAABLgAECn8eAAQFAAgJJhniEgAaAgAFAAgJJhniEgAaAgAKAAgJOhN8GQBwAQAGAAIJugjEdABWAAAAAA==.Catrathena:BAABLgAECn8VAAIaAAYJcxDTBAA3AQAaAAYJcxDTBAA3AQAAAA==.',
Cd='Cdxanti:BAAALgAFFAEJAQAAAA==.Cdxdrags:BAAALgADCgYJCQABLgAFFAEJAQAMAAAAAA==.',
Ce='Celeborn:BAAALgADCgYJDAAAAA==.Celeg:BAAALgAECgEJAgAAAA==.Celestine:BAAALgAECgcJCAAAAA==.Celithel:BAAALgAECgEJAQAAAA==.Celta:BAAALgADCgIJAgAAAA==.Celunelle:BAAALgAECgEJAQAAAA==.Cerulia:BAAALgADCgYJBgAAAA==.',
Ch='Chadgar:BAAALgAECgEJBgAAAA==.Chamanita:BAABLgAECn8iAAIVAAgJqhSLHgC+AQAVAAgJqhSLHgC+AQAAAA==.Chaospho:BAABLgAECn8nAAIZAAgJwBwmDAAmAgAZAAgJwBwmDAAmAgAAAA==.Charizzard:BAAALgAECgQJBAAAAA==.Charmelle:BAAALgADCgEJAQAAAA==.Chavo:BAAALgADCggJCAAAAA==.Chenzen:BAAALgAECgEJAQAAAA==.Chewbåcca:BAAALgADCgEJAQAAAA==.Cheweh:BAACLgAFFH8QAAMbAAUJXBZkBAAOAQAbAAUJXBZkBAAOAQAWAAEJaQD5MAA1AAAuAAQKfxkAAxsACQlkIAcHAH8CABsACQlkIAcHAH8CABYAAglJEFRNAG0AAAAA.Cheysuli:BAAALgADCgQJBAAAAA==.Choson:BAABLgAECn8aAAIEAAcJHgr7JQBEAQAEAAcJHgr7JQBEAQAAAA==.Chronô:BAAALgAECgcJEgAAAA==.Chudlee:BAAALgAECgYJEwAAAA==.Chumsticktwo:BAABLgAECn8UAAIcAAgJqRCAKgCOAQAcAAgJqRCAKgCOAQAAAA==.',
Ci='Cirillaa:BAAALgAECgcJEAAAAA==.Citi:BAAALgAECgQJBgAAAA==.Citinight:BAAALgAECgQJBAAAAA==.',
Cl='Clair:BAABLgAECn8rAAIGAAgJsh6ADQCAAgAGAAgJsh6ADQCAAgAAAA==.Clandestiny:BAAALgADCgIJAgAAAA==.Clef:BAAALgADCgcJBwAAAA==.Cleris:BAAALgAECgIJAgAAAA==.Cloudburstt:BAABLgAECn8hAAIVAAcJPRxTEQAwAgAVAAcJPRxTEQAwAgAAAA==.Clova:BAABLgAECn8aAAMHAAgJ0RkDEABWAgAHAAgJ0RkDEABWAgANAAYJugXcMADOAAAAAA==.Clëric:BAAALgAECgQJBQAAAA==.',
Co='Coler:BAAALgAECgYJDgAAAA==.Conelley:BAAALgADCgcJEAABLgADCgkJGAAMAAAAAA==.Conservative:BAAALgADCgEJAQAAAA==.Constdude:BAAALgADCgUJBQAAAA==.Cooldan:BAABLgAECn8dAAQTAAgJcxxoFgAvAgATAAgJcxxoFgAvAgAdAAEJaBhaKgBKAAASAAEJ8wwFcAA2AAAAAA==.Cooldude:BAAALgAECgYJCgAAAA==.',
Cr='Crabetable:BAABLgAECn8hAAMbAAkJTwpPBwC+AQAbAAkJTwpPBwC+AQAVAAEJ2QFwpAArAAAAAA==.Crankinette:BAAALgADCgMJAwAAAA==.Creation:BAAALgADCgcJCgAAAA==.Cremefraiche:BAAALgAECggJEgAAAA==.Critkiller:BAAALgADCgQJBAAAAA==.Crocodile:BAAALgADCgYJBwAAAA==.Crowsiv:BAAALgAECgkJEwABLgAECgQJAwAMAAAAAA==.Crulzilla:BAABLgAECn8ZAAICAAcJLxXnRQBqAQACAAcJLxXnRQBqAQAAAA==.',
Cu='Cupcakemeeow:BAABLgAECn8UAAIDAAYJSwZbjQD4AAADAAYJSwZbjQD4AAABLgAECggJHQABAIsPAA==.Cupcakemeow:BAABLgAECn8dAAQBAAgJiw/tMQDoAQABAAgJgw/tMQDoAQALAAcJ2gySEwB9AQAQAAIJeQJahgA2AAAAAA==.Curas:BAAALgAECgQJAwAAAA==.Curzøn:BAABLgAECn86AAIDAAkJvSU8CACGAwADAAkJvSU8CACGAwAAAA==.Cutecumber:BAAALgADCgQJBQABLgADCgYJDAAMAAAAAA==.',
Cy='Cynardria:BAABLgAECn8oAAIHAAkJoyTLBgAfAwAHAAkJoyTLBgAfAwAAAA==.Cynaris:BAAALgAECgEJAQAAAA==.',
['Cí']='Cínnabon:BAAALgADCgkJDwAAAA==.',
Da='Dabubblez:BAAALgADCgcJBwAAAA==.Daedengerek:BAABLgAECn8hAAIEAAgJAxeKGACjAQAEAAgJAxeKGACjAQAAAA==.Daggers:BAAALgADCgQJBAAAAA==.Daggren:BAABLgAECn8YAAIeAAYJfxMcHQAUAQAeAAYJfxMcHQAUAQAAAA==.Daiko:BAAALgAECgQJBwAAAA==.Danazaral:BAAALgAECgYJEgAAAA==.Danerrin:BAABLgAECn8eAAMCAAkJ2SG0BwDhAgACAAkJaSG0BwDhAgAfAAcJeh4xCAAGAgAAAA==.Dangermonk:BAAALgADCgEJAQAAAA==.Dangers:BAAALgAECgIJAgAAAA==.Danielsan:BAAALgAECgEJAQAAAA==.Danigos:BAAALgAFFAgJJQAAAQ==.Danocosmic:BAAALgAECgIJBAAAAA==.Danofyst:BAAALgADCgIJAgAAAA==.Danuwoa:BAABLgAECn8lAAIfAAkJAxLBDgCFAQAfAAkJAxLBDgCFAQAAAA==.Darkarrows:BAAALgADCgYJBgAAAA==.Darkritual:BAAALgADCgcJDgAAAA==.Daryss:BAAALgAECgIJAwAAAA==.Dawnshott:BAAALgAECggJDgAAAA==.Dawntotem:BAAALgAECgQJBAAAAA==.Dax:BAAALgADCgEJAQAAAA==.Daxoman:BAAALgAECgYJCgAAAA==.Daxxen:BAAALgADCgYJBgAAAA==.Daynkmyst:BAAALgADCgMJBQAAAA==.',
De='Deathadder:BAABLgAECn8lAAIBAAkJtiKeAwAAAwABAAkJtiKeAwAAAwAAAA==.Deathslayer:BAAALgAECgkJAgAAAA==.Deemonk:BAAALgAECggJEAABLgAECggJFQAQANQSAA==.Deification:BAABLgAECn8aAAIRAAYJIhpXDQBjAQARAAYJIhpXDQBjAQAAAA==.Delaena:BAAALgAECggJEQAAAA==.Delron:BAAALgAECgEJAQAAAA==.Delvari:BAAALgADCgEJAQAAAA==.Demins:BAAALgAECgQJCAAAAA==.Demiphant:BAAALgADCgcJBwAAAA==.Demonballz:BAABLgAECn8SAAIcAAYJXhcxNwBZAQAcAAYJXhcxNwBZAQAAAA==.Demonickirby:BAAALgADCgkJEgAAAA==.Denarrin:BAAALgAECgQJCgABLgAECgkJHgACANkhAA==.Dennirn:BAAALgADCgIJAgABLgAECgkJHgACANkhAA==.Deport:BAAALgADCgYJBgAAAA==.',
Di='Dianesis:BAAALgADCgYJBgAAAA==.Dieclowns:BAAALgAECgEJAQAAAA==.Dirtcat:BAAALgADCgIJAgAAAA==.Disgrace:BAAALgAECgEJAQAAAA==.Divínity:BAAALgAECgMJBAAAAA==.',
Do='Doomboome:BAAALgADCgkJEgAAAA==.Downstime:BAAALgAECgMJAwAAAA==.',
Dr='Dracthar:BAAALgAECgQJCQAAAA==.Draczeal:BAABLgAECn8WAAIgAAYJ2RdOCwCaAQAgAAYJ2RdOCwCaAQAAAA==.Dragonoffel:BAABLgAECn8bAAMTAAcJYQ6vQwBeAQATAAcJYQ6vQwBeAQAdAAEJAAC3HAAAAAAAAA==.Dragovade:BAABLgAECn8kAAQWAAgJsha7EwC5AQAWAAgJsha7EwC5AQAVAAIJ1hL+ZABqAAAbAAEJ3wogHwA4AAAAAA==.Drathor:BAABLgAECn8lAAITAAgJ8BwiJwDLAQATAAgJ8BwiJwDLAQAAAA==.Dravauk:BAAALgADCgQJBAAAAA==.Dreadlocke:BAAALgAECgIJAgAAAA==.Dreamtotem:BAAALgADCgcJBwAAAA==.Dreidels:BAAALgADCgkJCQABLgAECgkJLQAhAAwYAA==.Drick:BAAALgADCgYJBwAAAA==.Druishbeef:BAAALgAECgcJCwAAAA==.Drunkenbuddy:BAAALgAECgIJAgAAAA==.Drunky:BAABLgAECn8WAAIRAAYJvxUVEQAsAQARAAYJvxUVEQAsAQAAAA==.Drysua:BAACLgAFFH8FAAIKAAIJeAhtGgCTAAAKAAIJeAhtGgCTAAAuAAQKfzAAAgoACQmnF0AWADYCAAoACQmnF0AWADYCAAAA.',
Du='Duskmender:BAAALgADCgkJCgAAAA==.',
Dz='Dzret:BAABLgAECn8xAAIOAAYJLBHzcQAJAQAOAAYJLBHzcQAJAQAAAA==.',
['Dà']='Dàx:BAAALgAECgYJEQABLgAECgkJOgADAL0lAA==.',
['Dá']='Dáewoo:BAAALgADCgUJBQAAAA==.',
['Dè']='Dècypher:BAABLgAECn8nAAIWAAgJDhyrCQA+AgAWAAgJDhyrCQA+AgAAAA==.',
['Dí']='Díana:BAAALgADCgkJCgAAAA==.',
Ec='Echô:BAABLgAECn8eAAIOAAgJ6QURYwAnAQAOAAgJ6QURYwAnAQAAAA==.Echôes:BAAALgAECgEJAQAAAA==.',
Ed='Edbundance:BAABLgAFFH8FAAIYAAMJmBXbDQACAQAYAAMJmBXbDQACAQAAAA==.',
El='Ela:BAABLgAECn8VAAIOAAcJsxD9mQBKAQAOAAcJsxD9mQBKAQAAAA==.Elanuo:BAAALgAECgQJBwAAAA==.Elaynne:BAABLgAECn8lAAQQAAgJeyE3EAC7AgAQAAcJfCM3EAC7AgABAAYJcyHxHgDiAQALAAMJhxmPIAD5AAAAAA==.Eledis:BAABLgAECn8gAAMiAAkJoRniBQBQAgAiAAkJoRniBQBQAgAXAAIJuBDqJABcAAAAAA==.Elieth:BAAALgADCgUJBQABLgAECgMJAwAMAAAAAA==.Eliteelf:BAABLgAECn8cAAIQAAgJawVqEADnAAAQAAgJawVqEADnAAAAAA==.Ellenora:BAABLgAECn8fAAMHAAgJjgsNMgBVAQAHAAgJjgsNMgBVAQANAAIJggH3gQAuAAAAAA==.Ellessdee:BAABLgAECn8VAAIVAAYJfQ0GQQD/AAAVAAYJfQ0GQQD/AAAAAA==.Ellmer:BAABLgAECn8hAAIBAAgJ6h17FACTAgABAAgJ6h17FACTAgAAAA==.Elopeppe:BAABLgAECn8WAAMDAAYJJwRinQDYAAADAAYJJwRinQDYAAAjAAEJmAAoEgAcAAAAAA==.Elorro:BAACLgAFFH8OAAIEAAUJoQk2CABqAQAEAAUJoQk2CABqAQAuAAQKfycAAwQACQk4G3wSALsCAAQACQmgGnwSALsCACQAAwnQGtEoAKkAAAAA.Eltaizari:BAAALgAECgQJBAAAAA==.Elthiör:BAAALgADCgEJAQAAAA==.Eltion:BAAALgADCgkJDAAAAA==.Elunedorei:BAAALgADCggJCAAAAA==.Elwesingollo:BAAALgADCgcJDwAAAA==.',
En='Enilia:BAACLgAFFH8NAAMTAAQJ5xgCJwAjAQATAAQJ3xICJwAjAQASAAIJ2B+ZCQC+AAAuAAQKfykAAxIACQmpH6kBAFwCABIACAntHqkBAFwCABMABAnSGLRRADUBAAAA.Enrgizernelf:BAABLgAECn8WAAMKAAYJbR54EgC0AQAKAAYJbR54EgC0AQAGAAUJOwrcVwDWAAAAAA==.',
Eo='Eo:BAAALgADCgkJCQABLgADCgkJEgAMAAAAAA==.',
Er='Erathena:BAAALgAECgYJBgAAAA==.Eriya:BAABLgAECn8ZAAIOAAYJnSOdHwALAgAOAAYJnSOdHwALAgAAAA==.',
Es='Esmeray:BAABLgAECn8jAAIeAAgJZBhtCAAfAgAeAAgJZBhtCAAfAgAAAA==.',
Et='Eternîty:BAAALgAECgcJBwAAAA==.',
Eu='Euphonia:BAAALgAECgUJDgAAAA==.',
Ev='Eviantha:BAAALgADCgYJBgAAAA==.',
Ex='Excieo:BAAALgAECgUJBQAAAA==.Exgimm:BAAALgAECgEJAQAAAA==.Exinani:BAAALgAECgEJAgAAAA==.Exkira:BAAALgADCgIJAgAAAA==.',
Ey='Eyllis:BAABLgAECn82AAIGAAgJzRbxCwAoAgAGAAgJzRbxCwAoAgAAAA==.',
Ez='Ezekiel:BAAALgADCgMJAwAAAA==.',
Fa='Faedark:BAAALgAECgEJAQAAAA==.Falcios:BAAALgADCgkJEgAAAA==.Falcor:BAAALgAECgYJDgAAAA==.Falorin:BAAALgAECgEJAQAAAA==.Fancyface:BAAALgAECgMJBQABLgAECgUJCgAMAAAAAA==.Fanger:BAABLgAECn8ZAAQbAAYJhhkkEwDQAAAWAAYJGw2BWgDaAAAbAAUJ1BkkEwDQAAAVAAIJGwX5jgBbAAAAAA==.Fatthead:BAAALgADCgIJAgAAAA==.Faug:BAABLgAECn8VAAIgAAcJAQnILAANAQAgAAcJAQnILAANAQAAAA==.Fax:BAABLgAECn8VAAIZAAcJ3hG4MQAwAQAZAAcJ3hG4MQAwAQAAAA==.',
Fe='Fecalbutt:BAAALgADCgUJBQAAAA==.Ferang:BAABLgAECn8mAAMCAAgJUBWVSABhAQACAAgJmBOVSABhAQAfAAcJoxQIFwAYAQAAAA==.Fevion:BAAALgAECgQJBQABLgAECgYJCgAMAAAAAA==.',
Ff='Ffredyburger:BAAALgAECgEJAQAAAA==.',
Fi='Finduilas:BAABLgAECn8nAAMlAAgJICDZBgAeAgAlAAgJICDZBgAeAgAEAAQJhwOKhACsAAAAAA==.Fingaz:BAAALgAECgcJEwAAAA==.Firepower:BAABLgAECn8iAAMaAAgJBR10AwA3AgAaAAYJHyJ0AwA3AgADAAgJhBhzJAAUAgAAAA==.Firepriest:BAABLgAECn8ZAAMFAAYJNRO3GABuAQAFAAYJNRO3GABuAQAKAAEJJQ79UgAzAAAAAA==.Fistdard:BAAALgADCgIJAgAAAA==.Fistymisty:BAAALgAECgQJCAAAAA==.Fiôwyn:BAAALgADCgcJBwAAAA==.',
Fl='Flashspam:BAABLgAECn8VAAIIAAYJshA3KwA1AQAIAAYJshA3KwA1AQAAAA==.',
Fo='Foamcutout:BAAALgAECgcJDwAAAA==.Foog:BAABLgAECn8dAAIHAAgJLiKQFQCKAgAHAAgJLiKQFQCKAgAAAA==.Fordranger:BAAALgAECgUJBQABLgAECgYJDAAMAAAAAA==.Fourteen:BAACLgAFFH8XAAIZAAYJ2SDGAgAuAgAZAAYJ2SDGAgAuAgAuAAQKfy0AAhkACQluI7IBAF8DABkACQluI7IBAF8DAAAA.Fourus:BAAALgADCgkJEAAAAA==.',
Fr='Freakaleake:BAABLgAECn8aAAMOAAYJng8GdQACAQAOAAYJng8GdQACAQARAAEJPQ9pMQAyAAAAAA==.Fredburger:BAAALgAECgcJCwAAAA==.Freemochi:BAAALgADCgEJAQABLgAFFAYJEQATAPkRAA==.Freeport:BAAALgAECgUJBQABLgAFFAYJEQATAPkRAA==.Freesum:BAACLgAFFH8RAAITAAYJ+RERFABmAQATAAYJ+RERFABmAQAuAAQKfyMAAhMACAnaIf8RAOsCABMACAnaIf8RAOsCAAAA.Friweelin:BAAALgADCgEJAQAAAA==.Frostypillz:BAAALgADCgEJAQAAAA==.',
Fu='Fulgor:BAACLgAFFH8XAAIHAAYJ3B28AgDEAQAHAAYJ3B28AgDEAQAuAAQKfzkAAgcACQlZJSoBAJ4DAAcACQlZJSoBAJ4DAAAA.Funnymuffin:BAABLgAECn8jAAMSAAgJbxiVAwDpAQASAAgJbxiVAwDpAQATAAMJ9AVbmwCIAAAAAA==.Furyia:BAAALgAECgUJCAAAAA==.Fuzzleprime:BAABLgAECn8tAAIUAAkJkht3AgCNAgAUAAkJkht3AgCNAgAAAA==.Fuzzy:BAABLgAECn8ZAAMHAAYJIRSJMQBYAQAHAAYJIRSJMQBYAQANAAEJ8ARwYAAmAAAAAA==.',
Ga='Galatea:BAAALgAECgUJBgABLgAFFAEJAQAMAAAAAA==.Gannin:BAAALgADCgEJAQABLgAECgEJAQAMAAAAAA==.Garmart:BAABLgAECn8sAAQLAAkJCx/jAQDlAgALAAkJXx7jAQDlAgABAAkJJRcQFAAvAgAQAAcJaBMTLgDBAQAAAA==.Garnete:BAAALgADCgkJCQAAAA==.Gauza:BAABLgAECn8WAAIOAAYJ6hZqVwBDAQAOAAYJ6hZqVwBDAQAAAA==.',
Ge='Geb:BAAALgADCgkJCQAAAA==.Genga:BAAALgADCgQJBAAAAA==.',
Gh='Ghostlyone:BAAALgADCgYJBgAAAA==.Ghouldann:BAABLgAECn8iAAMSAAkJPRdnAwDwAQASAAkJPRdnAwDwAQATAAYJjxFppwAKAQAAAA==.Ghòstdòg:BAAALgAECgQJCAAAAA==.',
Gi='Gilday:BAAALgAECgUJEQAAAA==.Ginkins:BAAALgAECgUJBQAAAA==.',
Gl='Glagglag:BAABLgAECn8lAAIEAAkJyB1uCQBRAgAEAAkJyB1uCQBRAgAAAA==.Glasscannon:BAAALgAECgQJCAAAAA==.',
Go='Gohâm:BAAALgAECgcJCQAAAA==.Goosefuyuki:BAAALgADCgMJAwAAAA==.Gorothraex:BAABLgAECn8YAAIlAAcJtx17CADzAQAlAAcJtx17CADzAQAAAA==.',
Gr='Grailand:BAAALgAECgYJBwAAAA==.Graxion:BAABLgAECn8lAAIEAAcJmxRKGgCVAQAEAAcJmxRKGgCVAQAAAA==.Greggiiee:BAAALgAECgUJCgAAAA==.Grimdots:BAAALgADCgkJCwAAAA==.Grimlock:BAAALgADCgcJBwAAAA==.Grimmkrieger:BAAALgAECgIJAwAAAA==.Grimtusk:BAAALgAECgEJAgAAAA==.Grimzz:BAAALgAECgEJAQAAAA==.Grindelwald:BAAALgADCgkJLwAAAA==.',
Gu='Guak:BAAALgAECgQJCAAAAA==.Guakalock:BAAALgADCgkJGgAAAA==.Guernica:BAAALgADCgIJAgAAAA==.Gurfy:BAEALgADCgUJBQABLgAECgMJBAAMAAAAAA==.Guylos:BAAALgADCgcJEgAAAA==.',
Gw='Gwynorra:BAAALgAECgUJCAAAAA==.',
Gy='Gyradas:BAAALgAECgkJBwAAAA==.',
Ha='Habibi:BAABLgAECn8cAAIeAAgJ5Bz+BQBWAgAeAAgJ5Bz+BQBWAgAAAA==.Halooch:BAAALgAECgkJBwAAAA==.Hampter:BAAALgADCggJCAAAAA==.Hanwi:BAAALgADCgYJBwAAAA==.Haralda:BAAALgAECggJEwAAAA==.Haraluna:BAAALgADCgUJBQAAAA==.Harlequín:BAAALgADCgcJDgABLgADCgkJDwAMAAAAAA==.Harshblue:BAABLgAECn8jAAMOAAgJqyNxFADwAgAOAAgJqyNxFADwAgARAAQJvR97GABRAQAAAA==.Hasdormu:BAAALgADCgQJBAABLgAECgEJAQAMAAAAAA==.Hatsunixbay:BAAALgADCggJFAAAAA==.Hatt:BAABLgAECn8UAAMOAAcJvgzWgAB4AQAOAAcJvgzWgAB4AQARAAUJZQg9LgCeAAAAAA==.',
Hd='Hdmiport:BAABLgAECn8WAAIXAAkJkw2+DQB6AQAXAAkJkw2+DQB6AQAAAA==.',
He='Healeydan:BAAALgAECgIJAgAAAA==.Hebrews:BAAALgADCgMJAwAAAA==.Heddh:BAAALgAECgQJBAABLgAECgkJKAAHAKMkAA==.Heilen:BAAALgADCgIJAgAAAA==.Heiligfeuer:BAAALgAECgIJBAAAAA==.Hellscorn:BAABLgAECn8nAAIcAAgJ5wovUgADAQAcAAgJ5wovUgADAQAAAA==.Herrick:BAAALgAECgkJAgAAAA==.Heythanksman:BAABLgAECn8VAAIEAAYJuiL2KQASAgAEAAYJuiL2KQASAgAAAA==.Heyzues:BAAALgADCgcJDQABLgAECgYJEgAMAAAAAA==.',
Hi='Hippay:BAABLgAECn8aAAIUAAYJ/SFABgDoAQAUAAYJ/SFABgDoAQAAAA==.',
Ho='Hoid:BAABLgAECn8jAAMEAAgJ/hQtEgDeAQAEAAgJLRQtEgDeAQAkAAIJ5xLVLgB/AAAAAA==.Holynihalus:BAACLgAFFH8OAAIGAAUJfBykAwCgAQAGAAUJfBykAwCgAQAuAAQKfx0AAgYACQkUHyoIAMgCAAYACQkUHyoIAMgCAAAA.Holyph:BAAALgADCgEJAQAAAA==.Holysmacker:BAAALgADCgYJCAAAAA==.Holyspoons:BAABLgAECn81AAIOAAgJDBMUOQCcAQAOAAgJDBMUOQCcAQAAAA==.',
Hu='Huggs:BAAALgAECgcJCQAAAA==.Hunterama:BAAALgADCgcJCQAAAA==.Huntli:BAABLgAECn80AAIBAAkJGyTIAQA5AwABAAkJGyTIAQA5AwAAAA==.Hurthar:BAAALgADCgIJAgAAAA==.',
Hy='Hylaa:BAAALgADCgcJEQAAAA==.Hyrill:BAAALgADCgcJCgAAAA==.',
['Hé']='Hécate:BAACLgAFFH8HAAIZAAMJbA5LFwDHAAAZAAMJbA5LFwDHAAAuAAQKfyIAAhkACQmQHdwEAM0CABkACQmQHdwEAM0CAAAA.',
Ic='Icecreamcake:BAACLgAFFH8hAAMGAAcJfxOwAAAqAgAGAAcJfxOwAAAqAgAFAAMJLgCRKABFAAAuAAQKfyMAAwYACQnxDkwcAPsBAAYACQnxDkwcAPsBAAoABgm/EGs3ADMBAAAA.',
If='Ifingerpaint:BAAALgAFFAEJAwABLgAFFAcJEAAKAHMaAA==.',
Ik='Ikin:BAAALgADCggJEgAAAA==.',
Il='Illidansdad:BAAALgAECgcJCwAAAA==.',
Im='Imapickle:BAAALgAECgMJAwAAAA==.Imbrium:BAAALgAECgUJCgABLgAECgYJFgADAOYhAA==.',
In='Invoked:BAABLgAECn8UAAQgAAcJMhPcGQC+AQAgAAcJMhPcGQC+AQAJAAMJ+RoxQADmAAAmAAMJjQaMMgCBAAAAAA==.',
Io='Iorie:BAABLgAECn8VAAIBAAgJ9AZ5PQBXAQABAAgJ9AZ5PQBXAQAAAA==.',
Ip='Iphei:BAABLgAECn8pAAIGAAgJ2hO/EwC9AQAGAAgJ2hO/EwC9AQAAAA==.',
Ir='Iroko:BAAALgAECgEJAQAAAA==.Irulanni:BAABLgAECn8kAAIBAAgJShXAJwCzAQABAAgJShXAJwCzAQAAAA==.',
Is='Iseeyoubaby:BAAALgADCgIJAgAAAA==.Istariya:BAAALgADCgcJHAAAAA==.',
It='Ithoria:BAAALgADCgEJAQABLgAECgYJBwAMAAAAAA==.Itwillkeel:BAAALgADCgcJEgAAAA==.',
Iv='Iva:BAABLgAECn8eAAICAAkJhCIrBgD6AgACAAkJhCIrBgD6AgAAAA==.',
Ja='Jagerhunter:BAAALgADCgMJAwABLgADCggJCAAMAAAAAA==.Jagershaii:BAAALgAECgUJBwAAAA==.Jagruid:BAAALgADCggJCAAAAA==.Jalaven:BAABLgAECn8iAAIkAAcJJQ5uEABDAQAkAAcJJQ5uEABDAQAAAA==.Jamelanister:BAAALgAECgEJAQAAAA==.Jasar:BAAALgADCgYJBgAAAA==.Jayani:BAAALgADCgQJBwAAAA==.',
Je='Jesaryth:BAAALgAECgEJAgAAAA==.Jessicka:BAABLgAECn8WAAIDAAYJmAgrjQD4AAADAAYJmAgrjQD4AAAAAA==.Jesûs:BAAALgAECgEJAQAAAA==.Jethan:BAAALgAECgcJEAAAAA==.',
Jh='Jhalse:BAAALgADCgYJCgAAAA==.',
Ji='Jilley:BAAALgADCgQJBAAAAA==.Jinian:BAAALgADCgkJIQAAAA==.Jinyla:BAAALgAECgQJCAAAAA==.Jinz:BAAALgAECgYJDwAAAA==.',
Jo='Johchi:BAAALgADCgcJBwAAAA==.Johraco:BAABLgAECn8lAAMJAAgJgBrMEADLAQAJAAgJgBrMEADLAQAgAAEJwQGvLgAbAAABLgADCgcJBwAMAAAAAA==.Joust:BAAALgADCgYJCgAAAA==.',
Ju='Juke:BAAALgAECgYJEgABLgAECgkJNAABABskAA==.Justyra:BAAALgADCgkJCwAAAA==.Juve:BAABLgAECn8hAAMGAAcJDx/EBwB1AgAGAAcJDx/EBwB1AgAFAAYJJhGZIQAdAQAAAA==.Juyani:BAAALgAECgQJDQAAAA==.',
Ka='Ka:BAAALgADCgUJCAAAAA==.Kaeldon:BAAALgAECgQJBQAAAA==.Kaelenor:BAAALgADCgMJAwAAAA==.Kahma:BAAALgADCgYJBgAAAA==.Kailyn:BAAALgADCgcJBwAAAA==.Kaitia:BAAALgAECgEJAQAAAA==.Kaiyah:BAAALgAECgIJAwAAAA==.Kalrom:BAAALgADCgEJAQAAAA==.Kanab:BAAALgAECgcJDQAAAA==.Karazhak:BAAALgADCgEJAQAAAA==.Kasim:BAABLgAECn8ZAAIKAAYJWR3JEgCwAQAKAAYJWR3JEgCwAQAAAA==.Kato:BAAALgADCgkJEAAAAA==.Kaygome:BAABLgAECn8aAAIBAAcJJQ4bPwBRAQABAAcJJQ4bPwBRAQAAAA==.Kayllea:BAAALgADCgkJGgAAAA==.Kaysue:BAAALgADCgkJCQAAAA==.Kaytara:BAAALgAECgMJBAAAAA==.',
Ke='Keharn:BAAALgADCgcJEAAAAA==.Kelaros:BAAALgADCgUJCAAAAA==.Kelaroz:BAAALgAECgQJCAAAAA==.Kettock:BAAALgAECgQJEAAAAA==.Kevzorg:BAAALgAECgYJBgAAAA==.',
Kh='Khronis:BAAALgADCgIJAwAAAA==.',
Ki='Kilj:BAABLgAECn8tAAITAAkJZh2vCgCfAgATAAkJZh2vCgCfAgAAAA==.Killimanjaro:BAAALgAECgEJAQAAAA==.Kirsh:BAAALgADCgUJBQAAAA==.Kitherry:BAAALgAECgYJEwAAAA==.',
Kl='Klebsiella:BAAALgADCgMJBAAAAA==.',
Kn='Knomllik:BAABLgAECn8zAAMfAAgJZSarAQD4AgAfAAgJZSarAQD4AgACAAYJ5B08bwCqAQAAAA==.',
Ko='Koristil:BAAALgADCgkJDwAAAA==.Korrick:BAAALgADCggJEAAAAA==.Kowdrak:BAABLgAECn8ZAAMJAAgJkQSqKgABAQAJAAgJkQSqKgABAQAgAAYJoQaWNgC3AAAAAA==.Kowdrek:BAAALgADCgkJEAAAAA==.Kowmann:BAAALgADCgkJFQAAAA==.',
Kr='Kreapen:BAABLgAECn8ZAAMTAAYJ4hqDTgA+AQATAAQJxhyDTgA+AQASAAMJORQ0VwBpAAAAAA==.Krisdk:BAACLgAFFH8NAAMCAAUJ3BYtJgBTAQACAAQJ3BYtJgBTAQAfAAEJAAD3LgAAAAAuAAQKfy4AAwIACAmuI1UOAJACAAIACAn5IlUOAJACAB8ACAl3ILYFAEkCAAAA.Krisevoker:BAAALgADCgEJAQABLgAFFAUJDQACANwWAA==.Krystil:BAAALgAECgcJEwAAAA==.',
Kt='Ktosh:BAAALgADCgcJBwAAAA==.',
Ku='Kurenäi:BAAALgAECgkJDwAAAA==.Kurzul:BAAALgADCgEJAQAAAA==.',
Kw='Kwerin:BAAALgAECgUJCgAAAA==.',
Ky='Kyndrassa:BAAALgADCgQJBwAAAA==.Kynlari:BAAALgADCgEJAQAAAA==.Kypalgos:BAAALgAECgMJAwAAAA==.',
['Kí']='Kírî:BAAALgAECggJDwAAAA==.',
['Kú']='Kúma:BAABLgAECn8tAAMcAAkJXiI6AwAOAwAcAAkJXiI6AwAOAwAXAAEJSAvcLwAiAAAAAA==.',
La='Lachichi:BAAALgAECgEJAQAAAA==.Laquiche:BAAALgADCgEJAQAAAA==.Larat:BAAALgADCgMJBgAAAA==.Larrysmith:BAAALgADCgEJAQAAAA==.Layil:BAAALgAECgYJCwAAAA==.Lazrael:BAAALgAECgQJBAAAAA==.',
Le='Leathe:BAAALgADCgMJAgAAAA==.Ledana:BAAALgAECgQJBgAAAA==.Legolamb:BAABLgAECn8iAAInAAgJpRR7AwDIAQAnAAgJpRR7AwDIAQAAAA==.Leicht:BAAALgAECgUJDQAAAA==.Leitch:BAABLgAECn8UAAIoAAYJsBTDDABMAQAoAAYJsBTDDABMAQAAAA==.Leviasaint:BAABLgAECn8hAAIGAAgJ0w8rIABHAQAGAAgJ0w8rIABHAQAAAA==.',
Li='Lifeinsuranc:BAAALgADCgcJBwAAAA==.Lightstim:BAAALgAECgQJBwAAAA==.Lilbolt:BAAALgAECgEJAQAAAA==.Lilseven:BAAALgADCgEJAQAAAA==.Liorah:BAAALgAECgYJCgAAAA==.Liptan:BAABLgAECn8hAAMSAAgJ4A6+CgApAQASAAgJ4A6+CgApAQATAAEJqgED8QAeAAAAAA==.',
Lo='Lodtuspuch:BAAALgADCgMJAwAAAA==.Lohha:BAAALgAECgQJBQAAAA==.Lonesnipa:BAAALgADCgkJMwAAAA==.Looseyjoosey:BAAALgADCgkJKQABLgAECgkJLQAhAAwYAA==.Lorealee:BAAALgAECgEJAQAAAA==.Lotharious:BAAALgADCgcJBwAAAA==.Louiswu:BAABLgAECn8eAAIcAAcJWRNtNQBgAQAcAAcJWRNtNQBgAQAAAA==.Loursten:BAAALgADCgYJCwAAAA==.',
Lu='Luckyzounds:BAABLgAECn8WAAIGAAYJCQUEMADOAAAGAAYJCQUEMADOAAAAAA==.Lunariya:BAAALgAECgYJCwAAAA==.Lunâire:BAAALgADCgUJBQAAAA==.',
Ly='Lycandra:BAAALgAECgMJAwAAAA==.Lyroll:BAABLgAECn8aAAIPAAYJTRDQJgANAQAPAAYJTRDQJgANAQAAAA==.Lyssa:BAAALgAECgEJAgAAAA==.Lyz:BAAALgAECgQJDwAAAA==.',
['Lû']='Lûcca:BAAALgAECgQJBAAAAA==.',
Ma='Maahthu:BAAALgAECgYJBgAAAA==.Maddogtannen:BAAALgADCgEJAQAAAA==.Maddrezus:BAAALgADCgkJCQAAAA==.Madreazus:BAAALgADCgkJCQAAAA==.Madreezus:BAABLgAECn8hAAIEAAgJFCEIBwB9AgAEAAgJFCEIBwB9AgAAAA==.Maelinaria:BAAALgADCgEJAQAAAA==.Magdalayna:BAAALgADCgkJEgAAAA==.Magique:BAAALgADCgcJDQAAAA==.Mai:BAAALgAECgIJCQAAAA==.Makarov:BAABLgAECn8VAAIbAAcJhiUrBwB7AgAbAAcJhiUrBwB7AgAAAA==.Maladelyia:BAAALgADCgIJAgAAAA==.Mangodemon:BAACLgAFFH8PAAIcAAYJfRngCACaAQAcAAYJfRngCACaAQAuAAQKfyAAAxwACQlOIkEKADMDABwACQkKIUEKADMDABcAAgmpIHIbALUAAAAA.Mangopally:BAAALgAECgYJBwABLgAFFAYJDwAcAH0ZAA==.Mangoshammy:BAAALgAECgQJBQABLgAFFAYJDwAcAH0ZAA==.Mani:BAABLgAECn8aAAInAAYJhRwbBACmAQAnAAYJhRwbBACmAQAAAA==.Mariaus:BAAALgAECgQJBgAAAA==.Marifernanda:BAAALgAECgYJEwAAAA==.Marvel:BAAALgAECgMJAwAAAA==.Matteo:BAAALgADCgQJBAAAAA==.Maulynn:BAAALgAECgkJBwAAAA==.Mayuki:BAACLgAFFH8NAAIUAAQJbxt+AgBSAQAUAAQJbxt+AgBSAQAuAAQKfykAAhQACQlNJUwAAF0DABQACQlNJUwAAF0DAAAA.',
Mc='Mcboopies:BAAALgAECgIJAgAAAA==.Mckayle:BAABLgAECn8kAAMFAAgJqh42CgCWAgAFAAgJqh42CgCWAgAGAAcJLxs6IgDSAQAAAA==.Mckaylá:BAAALgAECgYJDAAAAA==.',
Me='Medorana:BAAALgAECgQJCAAAAA==.Mellxo:BAAALgAECgYJEQAAAA==.Mephiselenia:BAAALgADCgEJAQAAAA==.Meree:BAAALgADCgYJCQAAAA==.Meridion:BAAALgADCgEJAQAAAA==.Mewtilation:BAAALgAECgEJAgAAAA==.',
Mi='Midknieght:BAAALgADCgEJAQAAAA==.Midnis:BAAALgADCgQJBAAAAA==.Minalthor:BAAALgAECgUJBQAAAA==.Minthe:BAAALgAECgQJCAABLgAECgkJNAABABskAA==.Mirob:BAAALgAECgMJAwAAAA==.Mirrari:BAABLgAECn8WAAIGAAYJbhbxGQB9AQAGAAYJbhbxGQB9AQAAAA==.Missfrossty:BAAALgADCgkJCQAAAA==.Mistrnimbus:BAAALgADCgIJAgAAAA==.',
Mo='Mockrage:BAAALgAECgIJAgAAAA==.Mohim:BAAALgADCggJEAAAAA==.Mojoshi:BAAALgADCgIJAgAAAA==.Molten:BAABLgAECn8WAAIWAAYJkATrOgDAAAAWAAYJkATrOgDAAAAAAA==.Monkdeeznuts:BAAALgAECgMJAwAAAA==.Moonsault:BAAALgAECgYJBgAAAA==.Mooreland:BAAALgADCgcJCgAAAA==.Morado:BAAALgAECgEJAQAAAA==.Morganite:BAAALgADCgcJBwAAAA==.Morgomir:BAAALgAECgEJAQAAAA==.Moronica:BAAALgAECgMJAwAAAA==.Morsviridi:BAAALgADCgIJAgAAAA==.Mox:BAAALgADCgcJBwAAAA==.',
Ms='Mscabalistic:BAAALgADCgIJAgAAAA==.',
Mu='Murdrmittens:BAABLgAECn8ZAAIYAAgJORY/EQCvAQAYAAgJORY/EQCvAQAAAA==.Muyaa:BAAALgAECgQJBAAAAA==.',
My='Myrabeth:BAAALgAECgIJAgAAAA==.Mytternàkt:BAAALgAECgYJEgAAAA==.',
Na='Naldon:BAAALgAECgYJEwAAAA==.Naptimegames:BAAALgAECgUJBQAAAA==.Nararis:BAAALgADCgIJAgAAAA==.Nasmin:BAAALgAECgQJBgAAAA==.',
Ne='Nechta:BAAALgADCgMJBAAAAA==.Nemesyr:BAAALgAECgkJEgAAAA==.Nephtyys:BAABLgAECn8aAAIhAAYJpB6bBADGAQAhAAYJpB6bBADGAQAAAA==.Nerfbat:BAABLgAECn8WAAIcAAYJfCL2GQDuAQAcAAYJfCL2GQDuAQAAAA==.Nerus:BAAALgADCggJCAAAAA==.Nes:BAABLgAECn8gAAMXAAgJSQzKCgAiAQAXAAgJPQvKCgAiAQAiAAQJ6Ar3SQDKAAAAAA==.Nesaja:BAAALgADCgMJAwAAAA==.Netra:BAAALgADCgcJBwAAAA==.Neîth:BAAALgADCgkJMQAAAA==.',
Ni='Niavy:BAABLgAECn8cAAMVAAgJdiHyBwCuAgAVAAgJdiHyBwCuAgAWAAEJ1A2LaAAuAAAAAA==.Nicore:BAABLgAECn8UAAIiAAgJRBI1IgCrAQAiAAgJRBI1IgCrAQAAAA==.Nicorre:BAAALgADCggJCAAAAA==.Nightgecko:BAABLgAECn8kAAIQAAkJ/yA4AgBlAgAQAAkJ/yA4AgBlAgAAAA==.Nihaludan:BAAALgADCgUJBQAAAA==.Nikkiwood:BAAALgADCgYJCwAAAA==.Nineteen:BAAALgAECgcJCAABLgAFFAYJFwAZANkgAA==.Nivandria:BAAALgADCgYJBgAAAA==.',
No='Noanuki:BAAALgADCgcJDwAAAA==.Nogdem:BAABLgAECn8iAAIRAAgJKRlJBgAAAgARAAgJKRlJBgAAAgAAAA==.Nohkan:BAAALgAECgUJEgAAAA==.Noobkin:BAAALgAECgYJBgAAAA==.Nordthewise:BAAALgADCgMJBAAAAA==.Noshtsherloc:BAABLgAECn8bAAIgAAgJLRBdDQBwAQAgAAgJLRBdDQBwAQAAAA==.Notdos:BAABLgAECn8aAAIJAAYJzgfGOgAGAQAJAAYJzgfGOgAGAQAAAA==.Nothebest:BAAALgADCgMJAwAAAA==.Novanafel:BAAALgADCgUJBQAAAA==.Novaprime:BAAALgAECgQJCAAAAA==.Novastra:BAAALgAECgcJDwAAAA==.Noweijose:BAAALgADCgYJBgABLgAECgYJFgADAOYhAA==.',
Nu='Nudi:BAAALgADCgEJAQAAAA==.',
Ny='Nymphadorä:BAAALgADCgEJAQAAAA==.Nyxuraldusk:BAAALgADCgcJCwAAAA==.',
['Nù']='Nùrse:BAAALgAECgMJAwAAAA==.',
Ob='Oballa:BAAALgADCgQJBAAAAA==.Obeel:BAABLgAECn8hAAMoAAYJfA5bEAAUAQAoAAYJhQxbEAAUAQAUAAIJZRCsKABaAAAAAA==.',
Og='Oggers:BAAALgAECgUJCwAAAA==.',
Ot='Otosan:BAABLgAECn8pAAIVAAkJsg9nKQB3AQAVAAkJsg9nKQB3AQAAAA==.',
Ou='Outsiders:BAAALgADCgYJBgAAAA==.',
Pa='Paisàn:BAAALgAECgYJCQAAAA==.Paku:BAAALgADCgMJAwAAAA==.Pawsatyou:BAAALgAECgQJBQAAAA==.',
Pe='Peachiekeen:BAAALgAECgIJBAAAAA==.Peekãboo:BAACLgAFFH8NAAIeAAUJriMRBACWAQAeAAUJriMRBACWAQAuAAQKfzMAAh4ACAmJJXgBAAkDAB4ACAmJJXgBAAkDAAAA.Peewheewoo:BAAALgAECgIJAgAAAA==.Penguin:BAAALgAECgQJDAAAAA==.Pepae:BAACLgAFFH8FAAMDAAIJPBb4WwCuAAADAAIJPBb4WwCuAAAaAAEJmAGpAgA0AAAuAAQKfzAAAwMACQkaJH0UAC0DAAMACQkaJH0UAC0DABoABQksFPkGANoAAAAA.',
Ph='Phantom:BAAALgAECgMJBQAAAA==.Pholia:BAAALgAECgcJEQAAAA==.',
Pi='Pieni:BAAALgAECgQJBAAAAA==.Pinkrose:BAABLgAECn8WAAIBAAYJxAwAWwD/AAABAAYJxAwAWwD/AAAAAA==.Piñacolada:BAAALgADCgUJBQAAAA==.',
Pl='Platomatrixx:BAAALgAECgMJBgAAAA==.',
Po='Popnloc:BAAALgAECgIJAgAAAA==.',
Pr='Prayful:BAAALgAECgUJCQABLgAECggJFAAHAJ8WAA==.Priestsrsly:BAABLgAECn8aAAQFAAYJGSLsDwBAAgAFAAYJGSLsDwBAAgAGAAUJ8g/lSQARAQAKAAEJwQ00ZAAwAAAAAA==.',
Ps='Psyop:BAAALgAECgcJCwAAAA==.',
Pu='Pullmytail:BAABLgAECn8qAAQbAAgJ9COTAQC8AgAbAAgJ9COTAQC8AgAWAAQJgxOZUgD8AAAVAAMJeBB3dQC6AAAAAA==.Punish:BAAALgAECgIJAwAAAA==.Purrsian:BAAALgAECgUJCAAAAA==.',
['På']='Påntuflaz:BAAALgAECgcJBgAAAA==.',
Qb='Qberks:BAACLgAFFH8HAAICAAMJGxR6TQD0AAACAAMJGxR6TQD0AAAuAAQKfx4AAgIACAkiHpAfAMQCAAIACAkiHpAfAMQCAAAA.',
Qe='Qelizari:BAAALgAECgEJAQAAAA==.',
Qu='Queliel:BAAALgAECgUJBQABLgAFFAQJDQAcAH4TAA==.',
Qw='Qwelsha:BAAALgAECgEJAQAAAA==.',
Ra='Radtiz:BAAALgAFFAIJAwAAAA==.Raenin:BAABLgAECn8aAAINAAYJ1BmDIAAzAQANAAYJ1BmDIAAzAQAAAA==.Ragingdraem:BAAALgAECgEJBQAAAA==.Ragni:BAAALgAECgYJBgAAAA==.Raidei:BAABLgAECn8aAAMeAAYJphqtEgCDAQAeAAYJphqtEgCDAQAhAAEJBRHjHwAzAAAAAA==.Raimbish:BAAALgAECgEJAQAAAA==.Rainwater:BAAALgADCgYJBgAAAA==.Rajah:BAAALgAECgEJAQAAAA==.Rakeripwait:BAABLgAECn8nAAMNAAcJZh2DDQD0AQANAAcJaxyDDQD0AQAoAAYJexhbEACnAQAAAA==.Raon:BAAALgADCgYJBgAAAA==.Ratatosk:BAABLgAECn8gAAIiAAgJpAZlGAAfAQAiAAgJpAZlGAAfAQAAAA==.Ratchef:BAAALgAECgMJCgAAAA==.Raventempus:BAABLgAECn8lAAIDAAkJCRP/KAD+AQADAAkJCRP/KAD+AQAAAA==.Rawheadrexx:BAAALgAECgEJAwAAAA==.',
Re='Rearden:BAAALgADCgYJBgAAAA==.Redatfirst:BAAALgADCgcJDQAAAA==.Redpawedfox:BAABLgAECn8sAAIHAAkJRBiGDwBcAgAHAAkJRBiGDwBcAgAAAA==.Reemaru:BAAALgADCgcJCAAAAA==.Rekviem:BAAALgAECgYJEAAAAQ==.Relifus:BAABLgAECn8UAAIPAAcJyx/uIQDyAQAPAAcJyx/uIQDyAQAAAA==.Renshin:BAAALgADCgYJBgAAAA==.Reshu:BAAALgADCgYJBgAAAA==.Resteel:BAAALgAECgEJAgAAAA==.Retallica:BAABLgAECn8aAAIOAAcJ4AT5swAcAQAOAAcJ4AT5swAcAQAAAA==.Revanite:BAABLgAECn8WAAITAAYJmBdjfwBcAQATAAYJmBdjfwBcAQAAAA==.Rexy:BAAALgADCgcJCAAAAA==.Rexydh:BAAALgADCgYJCwAAAA==.Rexygos:BAAALgAECgUJCwAAAA==.',
Rh='Rhavaniel:BAAALgAECgYJEgAAAA==.',
Ri='Rikola:BAAALgAECgEJAQAAAA==.Rizay:BAAALgADCgYJBgAAAA==.',
Ro='Roderika:BAAALgAECgUJBgAAAA==.Rogmar:BAAALgADCgEJAQAAAA==.Romgar:BAAALgAECgMJAwAAAA==.Rorak:BAAALgAECgUJBQAAAA==.Rotisserie:BAAALgAECgEJAgAAAA==.Royalnewb:BAAALgAECgcJEQABLgAECggJJwAWAA4cAA==.Royston:BAABLgAECn8sAAIlAAkJJxCcCgDEAQAlAAkJJxCcCgDEAQAAAA==.',
Ru='Rucereal:BAAALgAECgYJDwAAAA==.Ruie:BAAALgADCgMJAwAAAA==.Runefire:BAAALgAECgQJBgAAAA==.Ruperd:BAABLgAECn8lAAIOAAcJdx4SJADzAQAOAAcJdx4SJADzAQAAAA==.Rushzen:BAAALgADCgkJEwAAAA==.Russell:BAAALgAECgMJAwAAAA==.Rustyaf:BAAALgADCgYJCgAAAA==.',
Ry='Rynsidious:BAABLgAECn8nAAIiAAgJAxpsCwDNAQAiAAgJAxpsCwDNAQAAAA==.',
['Rã']='Rãin:BAAALgAECgMJBwABLgAECggJIQANAF4WAA==.',
Sa='Sabelle:BAABLgAECn8WAAIBAAYJHwfBZwDaAAABAAYJHwfBZwDaAAAAAA==.Saebel:BAAALgAECgcJCgAAAA==.Saeton:BAABLgAECn8fAAIRAAkJmQ1gCwCJAQARAAkJmQ1gCwCJAQAAAA==.Sahlaris:BAABLgAECn8VAAINAAgJxgl1HQBJAQANAAgJxgl1HQBJAQAAAA==.Saladfingrs:BAACLgAFFH8OAAMHAAQJdh4FEQBLAQAHAAQJdh4FEQBLAQANAAEJ/A0yJwBLAAAuAAQKfyQAAgcACAnfIc0PALoCAAcACAnfIc0PALoCAAAA.Saladin:BAAALgADCgcJCwAAAA==.Salno:BAAALgAECgQJBAAAAA==.Salvora:BAAALgADCgMJAwAAAA==.Sam:BAAALgADCgIJAgAAAA==.Samsonite:BAAALgAECgcJDAAAAA==.Sargerik:BAAALgADCgMJAwAAAA==.Savreen:BAAALgADCgUJBQAAAA==.',
Sc='Scrubdh:BAACLgAFFH8LAAIcAAUJtRthCwB8AQAcAAUJtRthCwB8AQAuAAQKfxoAAxwACAkfI3wOAAsDABwACAkfI3wOAAsDACIAAQleEfJuADYAAAAA.',
Se='Sekhet:BAABLgAECn8tAAMKAAkJTBqkBQCBAgAKAAkJTBqkBQCBAgAGAAcJlButDwDwAQAAAA==.Sekstrasza:BAAALgADCgkJKgAAAA==.Selenika:BAAALgADCgIJAgAAAA==.Sera:BAAALgAECgEJAQAAAA==.Serethyne:BAAALgADCgQJBwAAAA==.Serrahunt:BAAALgAECgQJBAAAAA==.Serrik:BAAALgAECgYJAQAAAA==.Severia:BAAALgADCgQJBAAAAA==.',
Sh='Shacakes:BAAALgAECgYJDQAAAA==.Shamanoid:BAAALgAECgcJCAABLgAECgcJDgAMAAAAAA==.Shasta:BAABLgAECn8rAAIOAAkJLB39DQCPAgAOAAkJLB39DQCPAgAAAA==.Shear:BAAALgAECgMJAwABLgAFFAEJAQAMAAAAAA==.Shekelshaker:BAABLgAECn8tAAIhAAkJDBitAQB1AgAhAAkJDBitAQB1AgAAAA==.Shinymetat:BAAALgAECgEJAQAAAA==.Shozmonk:BAAALgAECgQJBQAAAA==.',
Si='Siik:BAAALgAECgEJAQABLgAECgcJDQAMAAAAAA==.Silaena:BAABLgAECn8aAAIVAAYJrQ88OQAjAQAVAAYJrQ88OQAjAQAAAA==.Silverlocke:BAABLgAECn8UAAIRAAcJzBCzEwALAQARAAcJzBCzEwALAQAAAA==.Sinstergates:BAAALgAECgcJEQAAAA==.Sinvyr:BAAALgAECgYJDQABLgAECggJGQAcAGYVAA==.Sinvyris:BAABLgAECn8ZAAIcAAgJZhXzNQAfAgAcAAgJZhXzNQAfAgAAAA==.',
Sk='Skagirl:BAAALgAECgYJEgAAAA==.Skillscales:BAACLgAFFH8PAAMJAAUJug0CFwArAQAJAAUJug0CFwArAQAmAAEJagboCgBOAAAuAAQKfzkAAwkACAkKJQcDAO0CAAkACAmrJAcDAO0CACYACAkCG9cEALYCAAAA.Skor:BAAALgAECgcJDAAAAA==.Skyblaze:BAAALgAECgkJBAAAAA==.Skyfallen:BAAALgAECgcJEwAAAA==.',
Sl='Sleepeh:BAAALgADCgUJBQAAAA==.Slimjim:BAAALgAECgIJAgABLgAECgYJFgADAOYhAA==.Slink:BAAALgADCgIJAgAAAA==.Slovik:BAAALgAECgcJEAAAAA==.',
Sm='Smarb:BAAALgAECgEJAQABLgAECgUJEAAMAAAAAA==.Smooth:BAAALgAECgYJCgAAAA==.',
So='Solanar:BAAALgADCgYJCAAAAA==.Solanea:BAABLgAECn8ZAAInAAgJHxmaAwADAgAnAAgJHxmaAwADAgAAAA==.Sonic:BAAALgAECgIJBAAAAA==.Sorcforce:BAAALgADCgMJAwAAAA==.Sorin:BAAALgADCgkJJQABLgAECgkJLQATAGYdAA==.Soultelage:BAAALgAECgMJAwAAAA==.Soupwiz:BAAALgAECgEJAQAAAA==.Sourwine:BAAALgAECgQJDgAAAA==.',
Sp='Sparklecakes:BAAALgAECgcJBwABLgAECggJJwAGAA8eAA==.Spritedk:BAAALgAECgYJEwAAAA==.Spritemonk:BAAALgAECgcJEQAAAA==.Spritepally:BAABLgAECn8lAAMIAAcJ7xxDGABQAgAIAAcJ7xxDGABQAgARAAYJDBeZDwBAAQAAAA==.',
St='Stalk:BAAALgAECgQJCgAAAA==.Starlørd:BAABLgAECn8cAAMNAAcJhhBoHwA7AQANAAcJhhBoHwA7AQAHAAIJ7waAugBRAAAAAA==.Stavilde:BAAALgAECgEJAgAAAA==.Stemavesa:BAAALgADCgkJGQABLgAECgkJKwAOACwdAA==.Stichy:BAAALgAECgQJBAABLgAECggJIQANAF4WAA==.Stormdancer:BAABLgAECn8lAAIbAAgJZSQ8AQDWAgAbAAgJZSQ8AQDWAgAAAA==.Stormtusk:BAAALgADCgYJBwAAAA==.Strangiatie:BAAALgADCgcJCgAAAA==.Stumpyfoot:BAABLgAECn8VAAIHAAcJlBf3RQCKAQAHAAcJlBf3RQCKAQAAAA==.Stygi:BAAALgAECgQJBAAAAA==.Stãrs:BAACLgAFFH8PAAINAAUJGhnLCQBdAQANAAUJGhnLCQBdAQAuAAQKfzgAAg0ACAm7JMoCAOwCAA0ACAm7JMoCAOwCAAAA.',
Su='Sugarmama:BAAALgAECgMJBQAAAA==.Sunstrap:BAAALgAECgEJAQAAAA==.Sunwarden:BAAALgAECgYJCAAAAA==.',
Sv='Svx:BAAALgADCgcJCAAAAA==.',
Sw='Switchcase:BAABLgAECn8fAAIHAAgJsB/VCAC8AgAHAAgJsB/VCAC8AgAAAA==.',
Sy='Sylviria:BAAALgADCgEJAQAAAA==.Syntharia:BAABLgAECn8rAAIJAAkJuQoCGACCAQAJAAkJuQoCGACCAQAAAA==.Syyiasia:BAAALgADCgcJBwAAAA==.',
Sz='Szintra:BAAALgAECgYJDAAAAA==.',
['Sê']='Sêrenn:BAAALgADCgIJAgAAAA==.',
['Së']='Sërpentine:BAAALgAECgQJBwABLgAECggJIQANAF4WAA==.',
Ta='Taffigosa:BAABLgAECn8tAAIJAAkJShthBQCWAgAJAAkJShthBQCWAgAAAA==.Taffy:BAAALgADCgYJBwAAAA==.Takodaddy:BAAALgADCgUJBQAAAA==.Taledol:BAAALgADCgcJCQAAAA==.Tanaelyn:BAAALgADCgEJAQAAAA==.Tanthel:BAABLgAECn8oAAIYAAgJ4xHlEgCdAQAYAAgJ4xHlEgCdAQAAAA==.Taroboba:BAAALgAECgYJBQAAAA==.Taursain:BAAALgAECgEJAQAAAA==.',
Tb='Tbh:BAAALgAECgcJEQAAAA==.',
Te='Telemacon:BAAALgADCgIJAgABLgADCggJCAAMAAAAAA==.Temple:BAAALgAECgQJBwAAAA==.Tental:BAAALgADCgcJCwAAAA==.Termduilas:BAAALgAECgEJAQAAAA==.Terraquis:BAAALgAECgcJEAAAAA==.Testarossa:BAAALgAECgIJAwABLgAECggJFQAbAIYlAA==.',
Th='Thalyon:BAAALgAECgcJBQAAAA==.Thekillagirl:BAAALgAECgYJDwAAAA==.Thiccbiddies:BAABLgAECn8sAAIEAAgJGxoqDAAoAgAEAAgJGxoqDAAoAgAAAA==.Thicums:BAEALgAECgMJBAAAAA==.Thompson:BAAALgADCggJEwAAAA==.Thorad:BAAALgADCgMJAwAAAA==.Thordrann:BAAALgADCgEJAQAAAA==.Thorgyllan:BAABLgAECn8XAAIOAAgJRBviKACBAgAOAAgJRBviKACBAgAAAA==.Thort:BAAALgAECgYJEgAAAA==.Thunderwings:BAAALgAECgMJAwAAAA==.',
Ti='Tiaramisu:BAABLgAECn8UAAIYAAgJTxLtHAD0AQAYAAgJTxLtHAD0AQAAAA==.Tienmu:BAABLgAECn8aAAIVAAcJOCQiBwC9AgAVAAcJOCQiBwC9AgABLgADCgkJEAAMAAAAAA==.Tigan:BAABLgAECn8bAAMcAAgJ5A/DMwBmAQAcAAgJ5A/DMwBmAQAXAAEJqw4XMQAeAAAAAA==.Tigerlily:BAAALgAECgEJAgAAAA==.Tigra:BAABLgAECn8dAAINAAgJwhDvGAByAQANAAgJwhDvGAByAQAAAA==.Timeweaver:BAABLgAECn8kAAMgAAkJkQ6/CADYAQAgAAkJkQ6/CADYAQAmAAIJCAeVGQArAAAAAA==.Tirank:BAAALgADCgUJBwAAAA==.Tirione:BAAALgAECgcJCAAAAA==.Tirmone:BAABLgAECn8bAAMZAAcJ2BciFAC8AQAZAAYJAxoiFAC8AQAYAAEJCBLaVwA7AAAAAA==.',
To='Toastshark:BAABLgAECn8VAAIDAAcJ6R5dbAD8AQADAAcJ6R5dbAD8AQAAAA==.Toirneach:BAAALgADCgIJAgABLgAECgQJCQAMAAAAAA==.Toranaar:BAAALgADCgkJCQAAAA==.Torapaw:BAAALgADCgkJIgAAAA==.Totorö:BAABLgAECn8hAAINAAgJXhZ5IQDxAQANAAgJXhZ5IQDxAQAAAA==.',
Tr='Trayfu:BAABLgAECn8WAAMYAAYJfwkMKADwAAAYAAYJfwkMKADwAAAZAAQJ2RE3LgDjAAAAAA==.Trice:BAAALgAECgEJAQABLgAECggJFQAPAKYUAA==.Trollie:BAAALgADCgEJAQAAAA==.Trostani:BAAALgADCgcJCgAAAA==.Truetotem:BAAALgAECggJEQAAAA==.Trusker:BAABLgAECn8lAAIhAAcJjR2jAwD0AQAhAAcJjR2jAwD0AQAAAA==.Trypticon:BAAALgADCgYJBgAAAA==.Tryst:BAAALgAECgIJAgAAAA==.',
Tu='Tullir:BAAALgADCgcJBwAAAA==.Tuo:BAAALgADCgIJAgAAAA==.Turniphead:BAABLgAECn8ZAAIRAAYJnhMREgAfAQARAAYJnhMREgAfAQAAAA==.',
Tw='Twitty:BAABLgAECn8mAAIZAAkJdB96AgAsAwAZAAkJdB96AgAsAwAAAA==.',
Ty='Tyravana:BAAALgADCgYJCAAAAA==.Tystriel:BAABLgAECn8WAAMOAAgJHw5KhwBsAQAOAAgJHw5KhwBsAQAIAAYJHAMPOwDSAAAAAA==.',
Ul='Ulasar:BAAALgAECgQJBQAAAA==.',
Un='Unknownn:BAAALgADCgcJCAAAAA==.Unrak:BAABLgAECn8ZAAIOAAcJihDNdQCPAQAOAAcJihDNdQCPAQAAAA==.Untarot:BAAALgAECgIJAwAAAA==.',
Up='Uptyhme:BAAALgADCgMJAwAAAA==.',
Ur='Urmaker:BAAALgAECgEJAQAAAA==.',
Ut='Utinni:BAAALgAECgYJEQAAAA==.',
Va='Vaitlynn:BAAALgAECgEJAQAAAA==.Valadrick:BAAALgAECgYJBgABLgAECggJFwADAOwXAA==.Valcia:BAAALgADCgcJCgAAAA==.Valdanyr:BAEALgAECgYJEwAAAA==.Valkarr:BAAALgADCgEJAQABLgAECgcJEAAMAAAAAA==.Valkyrîe:BAAALgAECgcJEAAAAA==.Valorfist:BAABLgAECn8hAAIIAAcJHh9/CwBbAgAIAAcJHh9/CwBbAgAAAA==.Vancleef:BAABLgAECn8VAAIhAAcJ/RUoCgCTAQAhAAcJ/RUoCgCTAQAAAA==.Vandar:BAAALgAECgcJEwAAAA==.Varmav:BAABLgAECn8cAAISAAgJQhSGDQDtAQASAAgJQhSGDQDtAQAAAA==.Varsi:BAABLgAECn8jAAIBAAkJgRzdDgBgAgABAAkJgRzdDgBgAgAAAA==.Varân:BAABLgAECn8iAAIIAAgJ6BstDQBDAgAIAAgJ6BstDQBDAgAAAA==.Vashtyn:BAAALgADCgIJAQAAAA==.Vask:BAAALgAFFAIJAgAAAA==.Vazula:BAAALgADCgQJBAABLgAECgcJGQACAC8VAA==.',
Ve='Vede:BAABLgAECn8aAAICAAYJyw45WgAyAQACAAYJyw45WgAyAQAAAA==.Velash:BAABLgAECn8sAAMcAAcJ+B1/JgCjAQAiAAYJXR05GQD8AQAcAAYJzRx/JgCjAQAAAA==.Velliria:BAABLgAECn8bAAITAAcJ9hgeRgD5AQATAAcJ9hgeRgD5AQAAAA==.Velyandril:BAAALgAECgQJBwAAAA==.Vendorin:BAABLgAECn8WAAMfAAYJEwy/HQDUAAAfAAYJ0gu/HQDUAAACAAUJJQcf9gCQAAAAAA==.Vendre:BAABLgAECn8kAAMcAAkJlh3/BwClAgAcAAkJUB3/BwClAgAXAAEJkSNlJQBYAAAAAA==.Venilor:BAAALgAECgUJCQAAAA==.Veroswen:BAAALgADCggJCAAAAA==.Verratanectu:BAAALgAECgcJAwAAAA==.Verratanikto:BAAALgAECgYJEAAAAA==.Verwínd:BAAALgADCgMJBwAAAA==.Vett:BAAALgAECgMJBwAAAA==.',
Vi='Vický:BAAALgADCgIJAwAAAA==.Virusgt:BAAALgAECgcJDQAAAA==.Vita:BAAALgADCgkJGgAAAA==.Vitner:BAAALgADCgMJAwABLgAECgkJGQAmAL4UAA==.',
Vk='Vkandis:BAAALgAECgEJAQAAAA==.',
Vo='Voidbeam:BAAALgAECgEJAQAAAA==.Volker:BAAALgADCgEJAQAAAA==.Voltaris:BAAALgAECgMJAwAAAA==.',
Vr='Vriska:BAAALgADCgMJAwAAAA==.',
['Vâ']='Vânden:BAABLgAECn8UAAIEAAgJZR/QGACFAgAEAAgJZR/QGACFAgAAAA==.',
Wa='Wakawaka:BAABLgAECn8oAAMFAAgJMB77BgB9AgAFAAgJMB77BgB9AgAGAAEJ0hfeeQBBAAABLgAECgkJJgAZAHQfAA==.Waq:BAAALgAECgUJBgAAAA==.Washackedd:BAABLgAECn8jAAIGAAgJ1w5SFQCrAQAGAAgJ1w5SFQCrAQAAAA==.',
We='Wemad:BAAALgAECgcJDgAAAA==.',
Wi='Wife:BAABLgAECn8sAAMEAAkJIyAEAwDkAgAEAAkJoh8EAwDkAgAlAAMJqA55IwCiAAAAAA==.Wildfirê:BAAALgAECgYJBgABLgAFFAUJEAALAJQjAA==.Winna:BAAALgADCgIJAgAAAA==.Witdh:BAAALgAECgYJCgAAAA==.Wittboy:BAAALgAECgMJAwAAAA==.',
Wo='Wolffy:BAAALgADCgQJBAAAAA==.Woop:BAABLgAECn8lAAIYAAcJfxyIDQDfAQAYAAcJfxyIDQDfAQAAAA==.Wormsloe:BAABLgAECn8dAAIVAAcJaRUQIACyAQAVAAcJaRUQIACyAQAAAA==.',
Wr='Wraîith:BAAALgADCgQJBAAAAA==.',
Xa='Xaida:BAABLgAECn8lAAIYAAcJAx+1DADsAQAYAAcJAx+1DADsAQAAAA==.Xaldania:BAAALgADCgkJIgAAAA==.',
Xe='Xeav:BAAALgADCgIJAgAAAA==.Xeev:BAAALgAECgEJAQAAAA==.',
Xu='Xuing:BAABLgAECn8lAAIZAAkJYiMJAQCQAwAZAAkJYiMJAQCQAwAAAA==.',
Ya='Yahweh:BAAALgADCgcJDgAAAA==.Yangtze:BAAALgAECgEJAQAAAA==.Yarro:BAABLgAECn8aAAIBAAcJfxSAOQDIAQABAAcJfxSAOQDIAQAAAA==.Yaxxa:BAAALgADCgEJAQAAAA==.',
Yo='Yorozu:BAAALgAECgkJDwAAAA==.Youngblud:BAAALgAECgQJCQAAAA==.Yourrorstfea:BAAALgADCgUJBQAAAA==.',
Yv='Yvarca:BAAALgAECgIJAgABLgAECgYJCwAMAAAAAA==.',
Za='Zaela:BAABLgAECn8eAAIDAAcJ8xtqPACyAQADAAcJ8xtqPACyAQAAAA==.Zaku:BAAALgADCgcJDAAAAA==.Zamadi:BAAALgADCgcJEgAAAA==.Zax:BAAALgAECgYJDgAAAA==.',
Ze='Zendeth:BAABLgAECn8fAAMgAAgJ6SBBCQDMAQAgAAgJ6SBBCQDMAQAJAAEJLxTmXwA7AAAAAA==.Zerlin:BAAALgAECgMJAwAAAA==.Zeroximo:BAABLgAECn8XAAIDAAgJ7BcZUwA+AgADAAgJ7BcZUwA+AgAAAA==.',
Zi='Zipline:BAABLgAECn8kAAMiAAgJ/Bn1DQChAQAiAAYJWBz1DQChAQAcAAcJFBnKKgCNAQAAAA==.',
Zm='Zmbie:BAAALgAECgEJAQABLgAECgcJGQADAFARAA==.',
Zo='Zogz:BAAALgAECgUJCwAAAA==.Zombiexcat:BAABLgAECn8ZAAIDAAcJUBGjTwB7AQADAAcJUBGjTwB7AQAAAA==.Zoraell:BAABLgAECn8iAAICAAgJFR1lFQBQAgACAAgJFR1lFQBQAgAAAA==.Zordiak:BAAALgADCgEJAQABLgAECgcJEgAMAAAAAA==.Zordiakzero:BAABLgAECn8VAAMkAAcJfRxzCwDqAQAkAAcJGRxzCwDqAQAlAAEJVR4cLwBVAAAAAA==.Zoroaster:BAAALgADCgkJGQAAAA==.Zortaek:BAABLgAECn8iAAIVAAkJrxptFwBaAgAVAAkJrxptFwBaAgAAAA==.',
Zu='Zuban:BAAALgADCgYJCgABLgAECgcJKQABAOEiAA==.Zuki:BAABLgAECn8pAAMBAAcJ4SKfGgD+AQAQAAcJdCBHGQBgAgABAAYJvyOfGgD+AQAAAA==.',
Zw='Zweibellion:BAABLgAECn8lAAMgAAcJOBZfCADiAQAgAAcJOBZfCADiAQAJAAcJ7RVYFQCaAQAAAA==.',
Zz='Zzhunger:BAAALgADCggJDwAAAA==.Zzlazzers:BAAALgAECgcJCAAAAA==.Zzyuniver:BAAALgADCgcJCQAAAA==.',
['Âr']='Ârês:BAABLgAECn8UAAMkAAYJHRKoEgAqAQAkAAYJAxKoEgAqAQAlAAUJZAmhIwChAAAAAA==.',
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
