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

local lookup = {'Shaman-Enhancement','Priest-Shadow','Hunter-Marksmanship','Monk-Windwalker','Unknown-Unknown','DemonHunter-Havoc','DemonHunter-Devourer','Druid-Restoration','Evoker-Augmentation','Evoker-Devastation','Priest-Discipline','Warlock-Demonology','Hunter-Survival','Hunter-BeastMastery','Rogue-Subtlety','Mage-Frost','DeathKnight-Unholy','Warrior-Fury','Paladin-Protection','Shaman-Restoration','Shaman-Elemental','Mage-Fire','Warrior-Arms','DeathKnight-Blood','Druid-Balance','Warrior-Protection','Druid-Feral','Druid-Guardian','Warlock-Destruction','Paladin-Holy','Rogue-Outlaw','Rogue-Assassination','Warlock-Affliction','DeathKnight-Frost','Paladin-Retribution','Monk-Mistweaver','Monk-Brewmaster','Priest-Holy','Mage-Arcane','Evoker-Preservation',}
local provider = {region='US',realm='Moonrunner',name='US',type='weekly',zone=46,date='2026-05-01',data={Ac='Acense:BAAALgAECgQJBgAAAA==.Acewing:BAAALgADCgkJCgAAAA==.Acidlock:BAAALgAECgEJAgAAAA==.Acidpriest:BAAALgAECgYJCgAAAA==.Acidshaman:BAAALgADCgYJBwAAAA==.',
Ad='Adacey:BAAALgAECgUJBgAAAA==.Adragon:BAAALgAECgYJCwAAAA==.',
Ae='Aedryll:BAAALgAECgYJDQAAAA==.Aeriden:BAAALgAECgEJAQAAAA==.Aesuga:BAABLgAECn8nAAIBAAgJOiEDAgBlAgABAAgJOiEDAgBlAgAAAA==.Aethelflaed:BAABLgAECn8TAAICAAYJyxg4FABgAQACAAYJyxg4FABgAQAAAA==.',
Ag='Agnolotti:BAAALgAECgUJCAAAAA==.',
Ai='Aimedjupiter:BAAALgAECgYJEQABLgAFFAMJBQADAL0ZAA==.Air:BAAALgADCgcJBwABLgAECgcJFgAEANsaAA==.Airlyn:BAAALgAECgUJCgAAAA==.Aisen:BAAALgADCgEJAQABLgADCgEJAQAFAAAAAA==.',
Ak='Aktras:BAAALgAECgUJDwAAAA==.',
Al='Alaunu:BAAALgADCgkJBgAAAA==.Aleas:BAAALgADCgcJGAAAAA==.Aliciab:BAAALgADCgQJBAAAAA==.Alkaid:BAAALgAECgEJAQAAAA==.Alndvia:BAAALgAECgYJCgAAAA==.Alponknuts:BAAALgAECgUJCwAAAA==.Alponkster:BAAALgADCggJEwABLgAECgUJCwAFAAAAAA==.Alunia:BAAALgAECgIJAgAAAA==.Alytheal:BAAALgAECgEJAQAAAA==.',
Am='Americow:BAAALgADCggJCwAAAA==.',
An='Anarky:BAAALgAECgkJEAAAAA==.Andarnah:BAAALgADCgQJBAAAAA==.Annunaki:BAAALgAECgIJAwAAAA==.Anthrfinpete:BAAALgAECgIJBgABLgAECgcJEQAFAAAAAA==.',
Ar='Arathenes:BAAALgADCgcJCQAAAA==.Archae:BAAALgADCgYJBgAAAA==.Archdemon:BAAALgAECgMJBAAAAA==.Ariannette:BAAALgAECgMJAwAAAA==.Arilyn:BAAALgADCgMJAwAAAA==.Arkhanx:BAAALgAECgQJBwAAAA==.Artemisia:BAAALgADCgkJFgAAAA==.Artichoke:BAABLgAECn8WAAMGAAcJpRDwKwBpAQAGAAYJIxLwKwBpAQAHAAMJ2wUDjAAyAAAAAA==.',
As='Ashamane:BAAALgADCgQJBwABLgAECgUJCAAFAAAAAA==.Ashanara:BAAALgADCgEJAQABLgAECgYJDQAFAAAAAA==.Ashy:BAAALgADCgUJBQAAAA==.Astrov:BAAALgAECgcJDgAAAA==.',
At='Athera:BAAALgADCggJCAAAAA==.',
Au='Auani:BAABLgAECn8iAAIIAAgJeSOxAgAfAwAIAAgJeSOxAgAfAwAAAA==.Augtistic:BAABLgAECn8oAAMJAAgJXh1GBgA6AgAJAAgJXh1GBgA6AgAKAAMJwRfVKwC+AAAAAA==.Aurani:BAAALgAECgEJAQAAAA==.',
Ay='Ayanna:BAAALgADCgkJFQAAAA==.',
Az='Azale:BAAALgAECgMJAwAAAA==.Azulagos:BAAALgADCgYJBgAAAA==.Azzeus:BAABLgAECn8YAAMCAAgJCRlmBgApAgACAAgJCRlmBgApAgALAAEJmxMbVwAzAAAAAA==.',
Ba='Babyrinsjr:BAAALgAECgYJDwAAAA==.Baeyn:BAAALgADCgYJBgABLgAECggJJAAMADohAA==.Bagel:BAABLgAECn8gAAQNAAgJxhr5CQDCAQANAAcJBBz5CQDCAQADAAUJARe9OgB0AQAOAAYJ/QxSVQBoAQABLgAFFAUJEwABAO0eAA==.Baile:BAAALgADCgEJAQAAAA==.Bakon:BAAALgAECgUJDAAAAA==.Balin:BAAALgADCgYJDgAAAA==.Ballerin:BAAALgADCggJDwABLgAECgUJCAAFAAAAAA==.Barrada:BAAALgAECgYJEAAAAA==.Barricay:BAAALgAECgYJBwAAAA==.',
Be='Bearcane:BAAALgADCgUJBQABLgAECggJHwAHACseAA==.Beardheals:BAAALgADCgQJBAAAAA==.Beardàddy:BAAALgAECgQJBQAAAA==.Bellamira:BAAALgADCgIJAgAAAA==.Benjarrey:BAAALgADCgQJBAAAAA==.Berea:BAAALgAECgYJDAAAAA==.',
Bi='Bigmeatyclaw:BAAALgAECgEJAgAAAA==.Billywitchdr:BAAALgADCgEJAQAAAA==.',
Bl='Blankdemonic:BAAALgAECgEJAQAAAA==.Bleedblue:BAABLgAECn8eAAIPAAcJRRPqCwCqAQAPAAcJRRPqCwCqAQAAAA==.Blueballmonk:BAAALgAECgUJCQAAAA==.Bluerare:BAABLgAECn8kAAIQAAgJiBgCGQAWAgAQAAgJiBgCGQAWAgAAAA==.',
Bo='Bobsgrundle:BAAALgAECgQJBAAAAA==.Bowlinna:BAAALgAECgQJBwAAAA==.',
Br='Brewrosia:BAAALgAECgQJBAAAAA==.Briiki:BAAALgAECgEJAQAAAA==.Brinnohms:BAAALgADCggJCwAAAA==.Broadsnatl:BAAALgADCgEJAQAAAA==.Bryxi:BAAALgADCgYJBgABLgAECggJGwARAJwXAA==.Brünhilde:BAABLgAECn8fAAILAAcJnxTuDwCPAQALAAcJnxTuDwCPAQAAAA==.',
Bs='Bstbll:BAACLgAFFH8NAAIIAAUJvxO9DgApAQAIAAUJvxO9DgApAQAuAAQKfxYAAggACQmUHgEKAPQCAAgACQmUHgEKAPQCAAAA.Bstwaves:BAAALgAECgQJBQAAAA==.',
Bu='Bubbleban:BAAALgADCgUJBQAAAA==.Bungxi:BAAALgADCgUJBgABLgAECggJGwARAJwXAA==.Buraddo:BAAALgADCgYJBgABLgAECgYJDwAFAAAAAA==.Burrata:BAAALgADCgkJCQAAAA==.Buttsnacks:BAABLgAECn8aAAISAAgJMBv3BgBCAgASAAgJMBv3BgBCAgAAAA==.',
Ca='Cairebear:BAAALgADCgIJAwAAAA==.Callistrah:BAAALgAECgcJEAAAAA==.Caltaa:BAABLgAECn8pAAITAAgJLCQXAgAgAwATAAgJLCQXAgAgAwAAAA==.Camael:BAAALgAECgUJCQAAAA==.Canarah:BAAALgADCgUJBQABLgAFFAMJCQAUAJMSAA==.Canverian:BAAALgAECgYJDwAAAA==.Carmedic:BAAALgADCgcJDQAAAA==.',
Ce='Celexa:BAAALgAECgQJBAABLgAECgQJDgAFAAAAAA==.Celtmon:BAAALgADCgEJAQAAAA==.',
Ch='Cha:BAAALgAECgEJAQAAAA==.Chapi:BAAALgAECgYJCQAAAA==.Chasseurfool:BAAALgAECgQJCQAAAA==.Chat:BAACLgAFFH8MAAIVAAQJTxmyBgBcAQAVAAQJTxmyBgBcAQAuAAQKfycAAhUACQl2GcgJAP8BABUACQl2GcgJAP8BAAAA.Chewi:BAAALgADCgEJAQAAAA==.Chickenlitle:BAAALgADCgUJBQAAAA==.Chickenwing:BAABLgAECn8gAAIWAAgJUh2LAABZAgAWAAgJUh2LAABZAgAAAA==.Chilin:BAAALgADCgMJAwABLgAECgMJAwAFAAAAAA==.Chilinevoke:BAAALgAECgMJAwAAAA==.Christano:BAAALgAECggJEQAAAA==.Christhecold:BAABLgAECn8oAAMXAAgJyxpjBwCbAQASAAYJRBYVOQDCAQAXAAYJlhdjBwCbAQAAAA==.Chrollo:BAAALgAECgUJCAAAAA==.Chronoknight:BAAALgADCgkJCQAAAA==.Chronson:BAAALgADCgEJAQAAAA==.Chunt:BAAALgAECgQJCQAAAA==.',
Cl='Clamscasino:BAAALgADCgIJAgABLgAECgYJCwAFAAAAAA==.Clarke:BAAALgADCgMJAwAAAA==.Cloudcrack:BAACLgAFFH8UAAIVAAUJ9hm4BgBcAQAVAAUJ9hm4BgBcAQAuAAQKfyEAAhUACQmQHf4KAOcCABUACQmQHf4KAOcCAAAA.',
Co='Cocoapuffs:BAAALgADCgIJAgABLgAECgcJFwAYABsZAA==.Cocotaso:BAAALgAECgEJAQABLgAFFAIJAwAFAAAAAA==.Codemon:BAABLgAECn8WAAIKAAYJNRY4BQBfAQAKAAYJNRY4BQBfAQAAAA==.Coldfusion:BAAALgADCgEJAQAAAA==.Condemn:BAAALgADCgEJAgAAAA==.Condiments:BAAALgAECgEJAQAAAA==.Cortar:BAAALgAECgcJBgAAAA==.',
Cy='Cylrhea:BAABLgAECn8UAAIIAAgJKyOeBADfAgAIAAgJKyOeBADfAgAAAA==.Cyntrill:BAAALgAECgQJBQAAAA==.',
Da='Dadderz:BAAALgADCggJCAAAAA==.Daddydruid:BAAALgAECgMJBAAAAA==.Dahunter:BAAALgAECgYJCAAAAA==.Dajoel:BAAALgAECgUJCAAAAA==.Dakinna:BAAALgADCgMJAwAAAA==.Dakotawolfe:BAAALgADCgUJBQAAAA==.Dalacia:BAAALgAECgcJEAAAAA==.Dannyrojas:BAAALgAECgEJAgAAAA==.Darknature:BAABLgAECn8jAAMIAAgJABMzHgCPAQAIAAgJABMzHgCPAQAZAAcJYg4cHAAbAQAAAA==.Darkodin:BAABLgAECn8WAAIRAAYJaQlHVQACAQARAAYJaQlHVQACAQAAAA==.Darkomen:BAAALgADCgcJEgABLgAECgcJHQARALUNAA==.Darkvlad:BAABLgAECn8dAAIRAAcJtQ2AOABYAQARAAcJtQ2AOABYAQAAAA==.Datnagadrake:BAACLgAFFH8IAAMSAAMJSA/8EgDvAAASAAMJkwv8EgDvAAAaAAIJXxUSCwCWAAAuAAQKfy0AAxIACAlmIckDAJECABIACAlmIckDAJECABoAAQmJIXI/AFUAAAAA.Davere:BAAALgADCgEJAQAAAA==.Dawinchy:BAABLgAECn8pAAQIAAkJiRRHNADXAQAIAAkJiRRHNADXAQAbAAcJcgthCQBTAQAZAAEJpQXbTQAkAAAAAA==.',
Dc='Dchalla:BAAALgADCgcJDQAAAA==.',
De='Deadlypsycho:BAAALgAECgYJEgAAAA==.Deadmanrise:BAAALgADCgUJBQAAAA==.Deathawakens:BAAALgAECgQJBQAAAA==.Deathlyill:BAAALgAECgUJCwAAAA==.Deathtouch:BAAALgADCgcJDAAAAA==.Decembër:BAABLgAECn8cAAIQAAcJbAeHWwAmAQAQAAcJbAeHWwAmAQAAAA==.Decimious:BAAALgAECgQJBwAAAA==.Dekutree:BAABLgAECn8VAAIcAAYJTQqLEgCVAAAcAAYJTQqLEgCVAAAAAA==.Dellistia:BAAALgAECgMJBQAAAA==.Delvan:BAAALgAECgIJAgAAAA==.Demiglace:BAAALgAECgYJBgAAAA==.Demonkilla:BAAALgAECgYJDgAAAA==.Denadan:BAAALgAECgEJAQABLgAECgcJHgAdAL8JAA==.Desdamona:BAAALgAECgYJEQAAAA==.Destrodemon:BAABLgAECn8jAAIHAAgJXRH/IABtAQAHAAgJXRH/IABtAQAAAA==.Deviltango:BAAALgADCggJCAAAAA==.Devorick:BAABLgAECn8fAAMMAAgJ5Bf6GQDaAQAMAAgJ5Bf6GQDaAQAdAAIJQxCmUQB5AAAAAA==.',
Di='Diadem:BAAALgAECgMJBAABLgAECggJJAAMADohAA==.Diathian:BAAALgAECgIJAgABLgAFFAUJEQAQAPMTAA==.Diaval:BAAALgAECgYJDwAAAA==.Dih:BAAALgADCgkJFQABLgAECggJHAANAHYSAA==.Dihlngthepal:BAAALgAECgEJAQAAAA==.Dirtyzealot:BAAALgADCgkJFwAAAA==.Disenchanted:BAAALgAECgYJBgABLgAECgcJGQAJAFAbAA==.Divineknight:BAAALgADCgkJFQAAAA==.Diyiya:BAAALgAECgYJCwAAAA==.',
Do='Doorki:BAAALgAFFAIJAwAAAA==.Doubleott:BAAALgADCgkJHQAAAA==.',
Dr='Drael:BAAALgADCgkJHwAAAA==.Draickin:BAABLgAECn8dAAIeAAcJLRPEEwC5AQAeAAcJLRPEEwC5AQAAAA==.Drekle:BAAALgAECgYJBgABLgAECgcJGAAIACITAA==.Drelian:BAAALgAECgIJAgAAAA==.Drenzel:BAAALgADCgYJCQAAAA==.Drevy:BAABLgAECn8WAAQPAAcJHRYXDgCJAQAPAAcJHRYXDgCJAQAfAAMJKQiSDABdAAAgAAEJAADUFwAAAAAAAA==.Drewsguy:BAAALgADCgkJGwAAAA==.Drexchan:BAAALgAECgYJCQAAAA==.Drexen:BAAALgADCgQJBAAAAA==.Drexy:BAAALgAECgEJAQAAAA==.Dropdahammer:BAAALgADCgUJBQAAAA==.Drumroleplz:BAABLgAECn8ZAAMJAAcJUBtdFQBUAQAKAAUJWSCUEwCrAQAJAAYJeRVdFQBUAQAAAA==.',
Ds='Dsanatrestk:BAABLgAECn8oAAMRAAkJ0STOAQA3AwARAAkJ0STOAQA3AwAYAAcJ1RpZEAAFAgAAAA==.',
['Dà']='Dàddybear:BAAALgAECgUJDQAAAA==.',
Ea='Earthsangel:BAAALgAECgcJCAAAAA==.',
Ec='Eclair:BAAALgAFFAIJAgAAAA==.',
Ed='Edralyia:BAAALgAECgMJBQAAAA==.',
Ei='Eilaurosa:BAABLgAECn8nAAIgAAkJPBJ4AgD7AQAgAAkJPBJ4AgD7AQAAAA==.',
El='Eldrinne:BAAALgAECgUJEAAAAA==.Elftuah:BAAALgADCggJCAAAAA==.Elfö:BAAALgAECggJEwAAAA==.Elizawrath:BAABLgAECn8fAAMTAAgJ+B5tBQCgAgATAAgJ+B5tBQCgAgAeAAUJlBHbWgAQAQAAAA==.Elkuco:BAAALgAECgIJAgAAAA==.Elthiss:BAABLgAECn8cAAIcAAcJjhSYCQA5AQAcAAcJjhSYCQA5AQAAAA==.',
Em='Emariel:BAAALgAECgEJAQAAAA==.',
En='Enchäntress:BAABLgAECn8UAAMMAAgJFgyMLQB2AQAMAAgJFgyMLQB2AQAhAAEJAACDNwAjAAAAAA==.Enfer:BAAALgADCgYJCAABLgAFFAQJDAAVAE8ZAA==.Enogg:BAAALgAECgEJAQAAAA==.Envi:BAABLgAECn8kAAIQAAgJMRgYHAADAgAQAAgJMRgYHAADAgAAAA==.',
Ep='Ephraìm:BAAALgADCgQJCAAAAA==.',
Er='Erianthe:BAABLgAECn8pAAIRAAgJDQo7MgBwAQARAAgJDQo7MgBwAQAAAA==.Erophien:BAAALgADCggJEQAAAA==.Erovael:BAAALgADCgQJBAABLgADCggJEQAFAAAAAA==.Erovynael:BAAALgAECgUJCQAAAA==.',
Ev='Eversong:BAAALgAECgYJDwAAAA==.Evhi:BAAALgAECgYJCQAAAA==.',
Ex='Exmar:BAAALgAECgMJAwAAAA==.',
Fa='Faewhisker:BAAALgADCgcJCwAAAA==.Falnor:BAAALgADCgkJDAAAAA==.Famine:BAABLgAECn8gAAMRAAgJCBzxMQBwAgARAAgJCBzxMQBwAgAiAAEJAAC4EwAAAAAAAA==.Fancyfeet:BAAALgADCgYJBwABLgAFFAUJDAAPAHwRAA==.',
Fe='Fearios:BAABLgAECn8XAAIYAAcJGxlQBwCrAQAYAAcJGxlQBwCrAQAAAA==.Febronia:BAAALgAECgUJBQAAAA==.Felbeast:BAAALgAECgYJBQAAAA==.Felbound:BAAALgAECgEJAQAAAA==.Felltheburn:BAAALgADCgEJAQAAAA==.',
Fi='Figmênt:BAAALgAECgUJDgABLgAECgYJCwAFAAAAAA==.Finatic:BAAALgAECgMJAwAAAA==.Fireproof:BAABLgAECn8bAAMTAAcJjiKPCABPAgATAAcJOiCPCABPAgAjAAcJyBv9OQA7AgAAAA==.Fistedwaffle:BAAALgAECgEJAQABLgAFFAIJAwAFAAAAAA==.Fistopher:BAAALgAECgEJAQAAAA==.',
Fj='Fjorskin:BAAALgADCgEJAQAAAA==.',
Fl='Flairdragin:BAAALgAECgUJCAAAAA==.Flare:BAAALgAECggJEgAAAA==.',
Fo='Forix:BAAALgADCggJDAAAAA==.',
Fr='Fries:BAAALgADCggJCAAAAA==.Frosttbyte:BAABLgAECn8YAAIQAAgJ2h64HAAAAgAQAAgJ2h64HAAAAgAAAA==.Frostytute:BAAALgADCgcJDwAAAA==.',
Fu='Funsies:BAAALgADCgEJAQAAAA==.',
Fy='Fyrrstorm:BAAALgADCgkJDAAAAA==.',
['Fë']='Fëiróx:BAAALgADCgYJBgAAAA==.',
Ga='Gallum:BAAALgADCgEJAQAAAA==.',
Ge='Getzi:BAABLgAECn8ZAAIjAAgJYCL8FQDlAgAjAAgJYCL8FQDlAgAAAA==.',
Gh='Ghavinflip:BAAALgAECgcJDgAAAA==.',
Gi='Gil:BAABLgAECn8fAAIHAAgJPyLeCABMAgAHAAgJPyLeCABMAgAAAA==.Gimlita:BAAALgAECgIJAgABLgAECggJGwARAJwXAA==.Gindraxx:BAAALgADCgEJAQAAAA==.',
Gl='Glocket:BAAALgADCgEJAQAAAA==.',
Go='Goatspace:BAAALgADCgcJDgABLgAECgcJHgAdAL8JAA==.Goettel:BAAALgAECgUJBQAAAA==.Gogmazios:BAAALgADCgEJAQAAAA==.Gogofisco:BAAALgAECgEJAgAAAA==.Gongagà:BAAALgAECgYJDAAAAA==.Goodnoodle:BAAALgADCgEJAQAAAA==.Goyum:BAAALgADCgQJBAAAAA==.',
Gr='Grankino:BAABLgAECn8WAAIbAAcJrhR5BgCfAQAbAAcJrhR5BgCfAQAAAA==.Grayves:BAAALgAECgUJBAAAAA==.Greenthumbs:BAAALgAECgYJCgAAAA==.Greyhulk:BAAALgAECgQJBwAAAA==.Grinlock:BAAALgADCgEJAQAAAA==.',
Gu='Guldanshower:BAAALgADCgIJAgAAAA==.Gurni:BAAALgADCgYJCAAAAA==.Guthan:BAAALgAECgEJAQAAAA==.',
Gw='Gwaelphypha:BAABLgAECn8bAAIRAAgJnBf3RAAmAgARAAgJnBf3RAAmAgAAAA==.',
Ha='Hakarii:BAAALgADCgYJDAAAAA==.Halliax:BAAALgADCgYJBgABLgAECggJJAAMADohAA==.Hamburglar:BAAALgADCgYJCAAAAA==.Hapkido:BAABLgAECn8qAAMkAAgJ1yGLAwC4AgAkAAgJ1yGLAwC4AgAEAAEJbQRPUgApAAAAAA==.Hardsus:BAAALgADCgYJCgAAAA==.Hawfmave:BAAALgAECgQJBAAAAA==.',
He='Heals:BAAALgAECgMJAwAAAA==.Healthpotion:BAAALgAECgMJAwAAAA==.Heartbroken:BAAALgAECgkJBwAAAA==.Hecate:BAAALgAECgYJDgAAAA==.Heidnik:BAAALgADCgQJBAAAAA==.Helvetica:BAAALgADCggJDwAAAA==.Heretic:BAAALgAECgUJCAAAAA==.',
Hi='Hillboy:BAAALgAECgYJBgAAAA==.Hippiehulk:BAAALgAECgEJAQAAAA==.',
Ho='Holydes:BAAALgADCgkJFgABLgAECgYJEQAFAAAAAA==.Holyshrimp:BAABLgAECn8jAAICAAgJGxkOCQD0AQACAAgJGxkOCQD0AQAAAA==.Honeydew:BAAALgADCgcJBAAAAA==.Hordor:BAAALgAECgEJAQAAAA==.Hotndot:BAAALgADCgcJCgAAAA==.',
Hu='Hulem:BAAALgADCgEJAQAAAA==.Hummakavulä:BAAALgAECgQJBwAAAA==.Hunkahunka:BAAALgAECgMJBAAAAA==.Huunaron:BAABLgAECn8VAAMeAAYJqBs2LwDGAQAeAAYJqBs2LwDGAQAjAAMJGAZiigCWAAAAAA==.',
Id='Idylwilde:BAAALgAECgQJCgAAAA==.',
Ie='Ienzo:BAAALgADCgUJBQAAAA==.',
If='Ifunny:BAAALgAECgcJCgAAAA==.',
Ih='Iheartoreos:BAABLgAECn8cAAMYAAYJxRB3EQADAQAYAAYJpBB3EQADAQAiAAQJLwntDgCzAAAAAA==.',
Il='Ilovefuta:BAAALgAECgQJBAAAAA==.',
In='Inferna:BAAALgADCgQJCAAAAA==.Ink:BAAALgAFFAMJAwAAAA==.Inmortuae:BAAALgAECgMJAwAAAA==.Instakill:BAAALgADCgYJCQAAAA==.Insulin:BAAALgADCgkJEgAAAA==.Invictae:BAAALgAECgYJDAAAAA==.',
Io='Iobo:BAACLgAFFH8NAAIHAAYJsxvZDgBYAQAHAAYJsxvZDgBYAQAuAAQKfxgAAgcACQl4IhMHAFYDAAcACQl4IhMHAFYDAAAA.',
Ir='Iradori:BAABLgAFFH8RAAIQAAUJ8xN6GgBhAQAQAAUJ8xN6GgBhAQAAAA==.Irønbane:BAAALgAECgEJAQAAAA==.',
Is='Iskandar:BAAALgAECgQJBwAAAA==.Isparian:BAABLgAECn8XAAIjAAYJNBlEMQB9AQAjAAYJNBlEMQB9AQAAAA==.Issior:BAAALgAECgIJAgAAAA==.',
Ja='Jamal:BAAALgADCgkJGwAAAA==.Jarco:BAEALgAFFAIJAgAAAA==.Jasmyn:BAAALgADCgEJAQAAAA==.Jasseca:BAAALgADCggJCAABLgAECggJGwARAJwXAA==.Java:BAABLgAECn8UAAIMAAcJ0gndQgApAQAMAAcJ0gndQgApAQAAAA==.',
Jo='Joedakilla:BAAALgAECgEJAQAAAA==.Jonorin:BAAALgADCgEJAQAAAA==.',
Js='Jshaman:BAAALgAECgUJCQAAAA==.',
Ju='Judoken:BAABLgAECn8VAAMPAAYJHQeDGAAPAQAPAAYJGAeDGAAPAQAgAAUJUwLkFACsAAAAAA==.Jupiterr:BAABLgAFFH8FAAIDAAMJvRkmEwALAQADAAMJvRkmEwALAQAAAA==.',
Ka='Kaadra:BAAALgAECgEJAQAAAA==.Kaelgen:BAAALgAECgMJAwAAAA==.Kaelkin:BAAALgAECgYJBwABLgAECgYJFwAUAC4XAA==.Kaelthlar:BAAALgADCgYJDAAAAA==.Kaelun:BAAALgAECgQJBQABLgAECgYJFwAUAC4XAA==.Kaelundrus:BAABLgAECn8XAAMUAAYJLhdXRwBkAQAUAAYJLhdXRwBkAQABAAUJtA+PGQAuAQAAAA==.Kainis:BAAALgAECgQJBgAAAA==.Kairia:BAAALgADCgEJAQAAAA==.Kalvinakri:BAAALgADCgkJDgAAAA==.Karasana:BAAALgAECgQJBAAAAA==.Karmus:BAAALgAECgYJCgAAAA==.Kastaspella:BAABLgAECn8VAAIQAAcJZQ3DQwBjAQAQAAcJZQ3DQwBjAQAAAA==.Kau:BAAALgAECgUJCQAAAA==.Kawant:BAAALgAECgIJAwAAAA==.Kaylnee:BAAALgAECgYJDQAAAA==.',
Ke='Keadin:BAAALgAECgMJBQAAAA==.Kearra:BAAALgADCgkJCQAAAA==.Kehayne:BAAALgADCgQJBAAAAA==.Keilas:BAAALgAECgcJDgAAAA==.Kerro:BAAALgAECgIJAwAAAA==.Kerron:BAAALgADCgMJAwAAAA==.Keyes:BAACLgAFFH8TAAIlAAYJABqYAQD8AQAlAAYJABqYAQD8AQAuAAQKfycAAiUACQlTIaUBAOACACUACQlTIaUBAOACAAAA.Keylala:BAAALgAECgYJDwAAAA==.',
Ki='Kiafera:BAAALgADCgMJAwAAAA==.Kickenmage:BAAALgADCgcJCAABLgAECgYJDwAFAAAAAA==.Kickentail:BAAALgAECgYJDwAAAA==.Kidx:BAAALgAECgMJAwAAAA==.Kirisham:BAAALgAECgQJBAAAAA==.Kirlia:BAAALgAECgMJBgAAAA==.Kishenia:BAAALgAECgEJAQAAAA==.',
Kl='Kleanx:BAAALgADCgQJBAAAAA==.Klymax:BAAALgADCgUJBQAAAA==.',
Ko='Kongor:BAAALgAECggJEwAAAA==.Korathazan:BAAALgADCgEJAQAAAA==.Korithelse:BAAALgAECgEJAQAAAA==.Korthea:BAAALgAECgIJAgAAAA==.',
Kr='Krispitreat:BAAALgAECgYJCwAAAA==.Kritnespears:BAAALgAECgYJDgAAAA==.Krobelus:BAABLgAECn8pAAMjAAgJVQskRgA3AQAjAAcJsgskRgA3AQAeAAYJVQXhZADoAAAAAA==.',
Kv='Kvedaheillr:BAAALgAECgMJAwAAAA==.Kvedaroðull:BAAALgADCgYJBwAAAA==.Kvedathulr:BAAALgADCgYJBgAAAA==.',
Ky='Kyluna:BAAALgAECgEJAQAAAA==.',
['Kè']='Kères:BAAALgAECgUJCAAAAA==.Kèrónos:BAAALgADCgkJHwAAAA==.',
['Kì']='Kìllstheweak:BAABLgAECn8nAAMiAAgJchHVAwCBAQAiAAgJdhDVAwCBAQAYAAYJ3QwLJwAGAQAAAA==.',
La='Lauralai:BAAALgADCgcJCAAAAA==.Lavendra:BAAALgADCgcJDwAAAA==.Lawkz:BAAALgAECgcJCAAAAA==.Layliah:BAACLgAFFH8QAAIZAAUJHCJABACCAQAZAAUJHCJABACCAQAuAAQKfzQAAhkACQm3JGAAAGUDABkACQm3JGAAAGUDAAAA.',
Le='Leaftemplar:BAAALgADCgYJBgAAAA==.Leedragoon:BAAALgADCgMJAwAAAA==.Legaia:BAAALgADCgYJCQAAAA==.Legendknewl:BAAALgAECgIJAgAAAA==.Lemmesapthat:BAAALgADCgEJAQAAAA==.Leviathonian:BAAALgAECgEJAQAAAA==.',
Li='Lightseeker:BAAALgAECgEJAQAAAA==.Lillinna:BAAALgADCgQJBAAAAA==.Lisithen:BAAALgADCgEJAQAAAA==.',
Lo='Loafai:BAABLgAECn8eAAQdAAcJvwkODADgAAAhAAYJgAg7BgAPAQAdAAYJ5QcODADgAAAMAAUJqAMI1QCwAAAAAA==.Lockrocks:BAABLgAECn8VAAIMAAYJOxXeNABXAQAMAAYJOxXeNABXAQAAAA==.Lorcán:BAAALgAECgMJBQAAAA==.Lormazlezrax:BAACLgAFFH8JAAIUAAMJkxKgFwDPAAAUAAMJkxKgFwDPAAAuAAQKfyEAAhQABwmtHxMZAE0CABQABwmtHxMZAE0CAAAA.',
Lu='Luis:BAAALgAECgQJBAAAAA==.Lumaron:BAAALgADCgEJAgAAAA==.Lunamizka:BAAALgADCgIJAgAAAA==.Lunella:BAAALgAECgMJAwABLgAECgUJCgAFAAAAAA==.Lunethira:BAAALgAECgUJCgAAAA==.Lustdeeznuts:BAABLgAECn8XAAIVAAYJixs7EQCYAQAVAAYJixs7EQCYAQAAAA==.',
Ly='Lylat:BAAALgAECgIJAgAAAA==.',
['Ló']='Lórdelrond:BAAALgADCgUJCgAAAA==.',
['Lú']='Lúpo:BAAALgAECgUJCAAAAA==.',
Ma='Machezemo:BAABLgAECn8dAAIQAAcJiiFAJADXAQAQAAcJiiFAJADXAQAAAA==.Madhatter:BAAALgAECgQJBgAAAA==.Mahalka:BAAALgAECgEJAQAAAA==.Maki:BAABLgAECn8WAAImAAYJfyTBBQBkAgAmAAYJfyTBBQBkAgAAAA==.Malegar:BAAALgADCgcJGAAAAA==.Malendor:BAABLgAECn8fAAIEAAgJZSbdAAAXAwAEAAgJZSbdAAAXAwAAAA==.Mammajamma:BAAALgAECgEJAwAAAA==.Manbearcat:BAAALgAECgYJBwAAAA==.Marcydaghoul:BAAALgADCgUJBQAAAA==.Marivoker:BAAALgADCgkJHQABLgAECgYJCwAFAAAAAA==.Marsvolta:BAAALgADCgYJBgAAAA==.Maruxus:BAABLgAECn8kAAMgAAgJPBK2AwCrAQAgAAgJPBK2AwCrAQAfAAYJfg9LBgBhAQAAAA==.Marvilla:BAAALgAECggJEQAAAA==.Marwen:BAAALgADCgkJGwAAAA==.Mathbrew:BAABLgAECn8gAAIlAAgJvSEqBQBaAgAlAAgJvSEqBQBaAgAAAA==.',
Mc='Mcchicken:BAAALgADCgIJAgAAAA==.Mclardragos:BAAALgAECgYJEwAAAA==.',
Me='Mehv:BAEALgAECgkJCwAAAQ==.Melindria:BAABLgAECn8UAAMZAAYJHw9zPwA0AQAZAAYJHw9zPwA0AQAcAAYJ5QH2GABWAAAAAA==.Mendicine:BAAALgAECgUJCgAAAA==.Menmoe:BAAALgAECgEJAQAAAA==.',
Mf='Mfdoom:BAAALgAECgMJAwAAAA==.',
Mi='Miacyn:BAAALgADCgkJFQAAAA==.Miladybast:BAAALgAECgYJDAAAAA==.Mirra:BAABLgAECn8VAAIOAAYJlgn6RwD6AAAOAAYJlgn6RwD6AAAAAA==.Misha:BAAALgADCgUJBQAAAA==.Missdorei:BAAALgADCgcJFAAAAA==.',
Mo='Mogged:BAABLgAECn8VAAIQAAYJASNYHgD2AQAQAAYJASNYHgD2AQAAAA==.Mojocity:BAAALgADCgYJCwAAAA==.Molai:BAAALgAECgcJAwAAAA==.Monkdangit:BAAALgAECgYJCQAAAA==.Morionso:BAAALgAECgYJDwAAAA==.Morphyrinsjr:BAAALgADCgQJBAABLgAECgYJDwAFAAAAAA==.Mortarion:BAABLgAECn8hAAIRAAgJJSC5EAA2AgARAAgJJSC5EAA2AgAAAA==.Moxxulae:BAAALgADCgkJCAAAAA==.Moõn:BAABLgAECn8YAAIJAAgJyAx2EgB0AQAJAAgJyAx2EgB0AQAAAA==.',
Mu='Murcié:BAABLgAECn8lAAMHAAgJ8RWkOAASAgAHAAgJ0xWkOAASAgAGAAYJHwkJOgAZAQAAAA==.Murdiûs:BAABLgAECn8bAAIkAAkJ2RkpBwBLAgAkAAkJ2RkpBwBLAgAAAA==.',
My='Myregards:BAAALgADCgYJBwAAAA==.Myspaceshria:BAAALgAECgUJDgABLgAECggJGwARAJwXAA==.Mythbruh:BAAALgAECgcJCQABLgAECggJIAAlAL0hAA==.Mythis:BAAALgAECgMJBAAAAA==.',
['Mó']='Mósh:BAAALgAECgYJBgAAAA==.',
Na='Nahane:BAAALgAECgEJAQAAAA==.Nahlur:BAAALgAECgMJAwAAAA==.Naoko:BAAALgAECgEJAQAAAA==.Nayrlock:BAABLgAECn8kAAQMAAgJOiFIGgC3AgAMAAgJOiFIGgC3AgAhAAUJtRdgEQAXAQAdAAQJuBCgQACyAAAAAA==.Nayuta:BAAALgADCgYJBQAAAA==.Nazal:BAAALgADCgEJAQABLgADCgEJAQAFAAAAAA==.',
Nc='Nc:BAAALgADCgIJAgABLgAECgEJAQAFAAAAAA==.Nctee:BAAALgAECgYJDQAAAA==.',
Ne='Necropally:BAAALgAECgEJAQAAAA==.Necrotizor:BAABLgAECn8aAAMMAAgJYxrZJwCPAQAMAAgJYxrZJwCPAQAdAAEJPRVdHgBCAAAAAA==.Neonsalmandr:BAAALgAECgEJAQAAAA==.Nerrol:BAAALgADCgkJCQAAAA==.',
Ni='Nialliv:BAAALgADCgcJCQAAAA==.Nidvin:BAAALgAECgQJEAAAAA==.Nightsmoke:BAAALgAECgQJBQAAAA==.',
Nk='Nkb:BAAALgAECgIJAgAAAA==.',
Nn='Nnoitra:BAAALgADCgcJBwAAAA==.',
No='Noceman:BAAALgADCgEJAQAAAA==.Nock:BAAALgAECgYJBwAAAA==.Nolanel:BAAALgAECgEJAQAAAA==.Noll:BAAALgADCgUJBQAAAA==.Nonattarius:BAAALgAECgYJCwAAAA==.Norezfou:BAABLgAECn8hAAMmAAgJTxxdCwCaAgAmAAgJTxxdCwCaAgACAAEJ2xf3WwBFAAAAAA==.Nornir:BAAALgAECgIJAgAAAA==.Norran:BAAALgAECgcJDgAAAA==.Norvera:BAAALgAECgIJAgAAAA==.Notalice:BAAALgAECgUJBQAAAA==.Notmywife:BAAALgAECgYJDQAAAA==.Novakri:BAAALgADCgMJAwAAAA==.',
Nu='Nuker:BAAALgAECgUJCAAAAA==.Nurobi:BAABLgAECn8bAAIZAAgJYhNkDwCbAQAZAAgJYhNkDwCbAQAAAA==.Nuundix:BAAALgAECgUJCAAAAA==.',
Ny='Nysel:BAAALgAECgkJAQAAAA==.Nysera:BAAALgADCggJCAAAAA==.Nyxy:BAAALgAECgUJCAAAAA==.',
Oc='Ocey:BAAALgADCgYJCwAAAA==.',
Od='Odyn:BAAALgAECgYJEQAAAA==.',
Oo='Ooyu:BAAALgAECgUJCwAAAA==.',
Or='Orangepeel:BAAALgADCgUJBQAAAA==.Oridk:BAAALgAECgUJDQABLgAFFAMJBgANAO4dAA==.Orimage:BAAALgADCgkJDAABLgAFFAMJBgANAO4dAA==.Oripal:BAAALgAECgUJBQABLgAFFAMJBgANAO4dAA==.Oríon:BAACLgAFFH8GAAINAAMJ7h2XBwAfAQANAAMJ7h2XBwAfAQAuAAQKfx4AAw0ACAneHp8FALACAA0ACAneHp8FALACAAMABQlqFupSAAABAAAA.',
Ou='Outofmyele:BAAALgADCgQJBAAAAA==.',
Ow='Owoker:BAAALgAECggJDwAAAA==.',
Pa='Pablo:BAABLgAECn8VAAIbAAcJ3xl7CwAHAgAbAAcJ3xl7CwAHAgAAAA==.Pancaked:BAAALgAECgEJAQABLgAFFAUJEwABAO0eAA==.Pancakedup:BAAALgAECgcJDAABLgAFFAUJEwABAO0eAA==.Pandozer:BAAALgAECggJEAAAAA==.Pankratos:BAABLgAECn8VAAMlAAgJiyOzFABoAgAlAAgJiyOzFABoAgAEAAMJMiBcGQAbAQAAAA==.Papaspud:BAABLgAECn8jAAImAAgJbw5WFABwAQAmAAgJbw5WFABwAQAAAA==.Paradias:BAACLgAFFH8MAAIPAAUJfBEqDQANAQAPAAUJfBEqDQANAQAuAAQKfyIAAw8ACAkYIPMMAMoCAA8ACAn8H/MMAMoCACAABgmxFzEMAGIBAAAA.Pastor:BAAALgADCgYJCQAAAA==.Patpat:BAAALgADCgcJBgAAAA==.Paxxfist:BAABLgAECn8aAAIkAAgJPA/MFwBKAQAkAAgJPA/MFwBKAQAAAA==.',
Pe='Peachdevil:BAAALgADCgQJBAAAAA==.Penryn:BAAALgAECgEJAQAAAA==.Pentive:BAABLgAECn8VAAIbAAgJpxs5BQC9AgAbAAgJpxs5BQC9AgAAAA==.Peppersham:BAAALgAECgYJDwAAAA==.Pepromene:BAAALgADCgQJBAAAAA==.Perff:BAAALgADCgYJBQAAAA==.Perhaps:BAABLgAECn8cAAIlAAgJGSKLBwANAwAlAAgJGSKLBwANAwAAAA==.Petesdragin:BAAALgAECgcJEQAAAA==.',
Pf='Pfftpfft:BAAALgAECgYJCgAAAA==.',
Ph='Phatdanny:BAABLgAECn8VAAIjAAgJZBjCFgAFAgAjAAgJZBjCFgAFAgAAAA==.Phatdumpy:BAABLgAECn8cAAQNAAgJdhJzCgC6AQAOAAcJcROrOgDEAQANAAgJ+AxzCgC6AQADAAQJ7wrhXADOAAAAAA==.Phattphatt:BAABLgAECn8bAAIbAAcJ+RkhBQDLAQAbAAcJ+RkhBQDLAQAAAA==.Phonycheese:BAAALgAECgYJDAAAAA==.Phur:BAAALgAFFAIJBAAAAA==.',
Pi='Pinbal:BAAALgAECgQJBAAAAA==.Pixen:BAAALgAECggJDgAAAA==.',
Pl='Plagueiss:BAABLgAECn8cAAIRAAgJjhrNPABEAgARAAgJjhrNPABEAgAAAA==.',
Po='Pocalypse:BAAALgAECgYJBQAAAA==.Portstar:BAABLgAECn8WAAMQAAgJQQwsPgBzAQAQAAgJDQksPgBzAQAnAAYJyA1IBQDxAAAAAA==.',
Pr='Precast:BAAALgADCgUJCgAAAA==.Prestoresto:BAAALgAECgEJAQAAAA==.Prieske:BAAALgAECgYJEgAAAA==.Primed:BAABLgAECn8pAAIbAAgJIA6ZBgCcAQAbAAgJIA6ZBgCcAQAAAA==.Privxd:BAABLgAFFH8IAAIIAAQJvhj2CQA5AQAIAAQJvhj2CQA5AQAAAA==.Prunesa:BAAALgADCgcJBQAAAA==.',
Pu='Pungla:BAAALgAECgIJAQAAAA==.',
['Pî']='Pîper:BAAALgADCgYJBgAAAA==.',
['Pï']='Pït:BAAALgAECgYJDAAAAA==.',
Qp='Qprawindfury:BAAALgAECgQJCAAAAA==.',
Qu='Quadtwat:BAAALgAECgQJBwAAAA==.Quahogger:BAAALgAECgQJBgAAAA==.',
Ra='Radical:BAAALgAECgYJBwAAAA==.Railyard:BAAALgADCgMJAwABLgAECgIJAgAFAAAAAA==.Raivn:BAAALgADCgEJAQAAAA==.Rajasta:BAAALgAECgIJAwAAAA==.Rajzova:BAAALgADCgcJCgABLgAECgYJDAAFAAAAAA==.Randomclown:BAAALgADCgYJCgAAAA==.Rapi:BAAALgAECgMJAwAAAA==.Rascalfats:BAAALgAECgMJAwAAAA==.Rashii:BAAALgAECgYJDAAAAA==.Rawor:BAABLgAECn8WAAIMAAYJvg8kQgArAQAMAAYJvg8kQgArAQAAAA==.',
Re='Rebaderchi:BAABLgAECn8fAAIHAAgJKx6kGQC6AgAHAAgJKx6kGQC6AgAAAA==.Relyne:BAAALgADCgYJBgAAAA==.Remo:BAAALgADCgcJCQAAAA==.Remoria:BAAALgAECgYJBgAAAA==.Renildan:BAAALgAECgYJCQAAAA==.Renscope:BAAALgADCgUJBQAAAA==.Resala:BAAALgADCgYJBgAAAA==.Rev:BAAALgADCgMJAwAAAA==.Revanhawk:BAAALgADCgkJEQAAAA==.Revna:BAAALgADCgcJBwAAAA==.Rezputan:BAAALgAECggJEQAAAA==.',
Rh='Rholand:BAAALgAECgYJCQAAAA==.',
Ri='Rind:BAAALgAECgYJCAAAAA==.Rioken:BAABLgAECn8cAAMMAAgJhBgxFwDtAQAMAAgJhBgxFwDtAQAdAAEJgxB2bgA4AAAAAA==.Riolobo:BAAALgADCgIJAgAAAA==.Riorage:BAAALgAECgYJEQAAAA==.Ritz:BAAALgAECgEJAQAAAA==.Rizzoy:BAABLgAECn8hAAISAAYJzBuWEgCjAQASAAYJzBuWEgCjAQAAAA==.',
Ro='Rohoth:BAAALgADCgMJAwAAAA==.Rollo:BAAALgADCgYJDwAAAA==.Rolor:BAAALgADCgYJBgAAAA==.Rookiefister:BAAALgADCgEJAgAAAA==.Ross:BAECLgAFFH8IAAIkAAQJMyOiBQCeAQAkAAQJMyOiBQCeAQAuAAQKfxsAAiQABgmpJekIACICACQABgmpJekIACICAAAA.Rovyr:BAABLgAECn8gAAMoAAgJ9x+EAQDfAgAoAAgJ9x+EAQDfAgAKAAEJuAHhRQAeAAAAAA==.',
Ru='Ruckabis:BAABLgAECn8bAAMUAAgJVB89DQAZAgAUAAgJVB89DQAZAgAVAAEJPgcqUwAwAAAAAA==.Rundeezyy:BAAALgADCgYJCQAAAA==.',
Ry='Rylos:BAAALgAECggJEgAAAA==.Rytotem:BAAALgAECgMJBQAAAA==.Ryumi:BAAALgADCgkJCwAAAA==.Ryvington:BAAALgADCgYJCAAAAA==.',
Sa='Saansula:BAAALgAECgUJCAAAAA==.Sabian:BAAALgAECggJEAAAAA==.Saintjeb:BAAALgAFFAIJAwAAAA==.Saitami:BAAALgAECgEJAQAAAA==.Saitamå:BAAALgAECgYJDAAAAA==.Salinity:BAABLgAECn8YAAMdAAcJmCNtBwBRAgAdAAcJRSBtBwBRAgAMAAcJsR8gKACOAQAAAA==.Samanaras:BAAALgAECgUJDQAAAA==.Sanari:BAAALgADCgMJAwAAAA==.Santiago:BAAALgAECgQJCQAAAA==.Saratoga:BAAALgAECgcJDQAAAA==.Sarkana:BAABLgAECn8YAAIeAAgJehjSDQD9AQAeAAgJehjSDQD9AQAAAA==.Sarticor:BAAALgAECgEJAQAAAA==.Sassquatch:BAAALgAECgYJEwAAAA==.Saxonn:BAABLgAECn8dAAMVAAcJnQyxHgAiAQAVAAcJnQyxHgAiAQAUAAMJaQNAiABzAAAAAA==.Saydis:BAAALgAECgMJBgAAAA==.',
Sc='Schuftt:BAAALgAECgUJDAAAAA==.',
Se='Seafoodtower:BAAALgAECgEJAQAAAA==.Sebattan:BAAALgAECgEJAQAAAA==.Seleine:BAAALgADCgEJAQABLgAECggJJAAQADEYAA==.Sello:BAAALgAECgEJAgAAAA==.Seltzers:BAAALgADCgQJCgAAAA==.Selunella:BAAALgADCgEJAQABLgAECgUJCgAFAAAAAA==.Selvester:BAABLgAECn8WAAIlAAYJtCQOCAASAgAlAAYJtCQOCAASAgAAAA==.Senadria:BAAALgAECgUJEQAAAA==.Senseishifu:BAABLgAECn8YAAIlAAgJiQ3SPgBKAQAlAAgJiQ3SPgBKAQAAAA==.Seorsen:BAAALgADCgcJEAAAAA==.Servinghunt:BAAALgAECgYJBgAAAA==.Sevalandre:BAAALgADCgYJBgABLgAECggJGwARAJwXAA==.',
Sh='Shamatrest:BAAALgAECgEJAgABLgAECgkJKAARANEkAA==.Shamina:BAABLgAECn8VAAIBAAcJqw4lEAC1AQABAAcJqw4lEAC1AQAAAA==.Shamite:BAAALgAECgMJAwABLgAECgYJBwAFAAAAAA==.Shammalin:BAABLgAECn8eAAMVAAcJVwoEHwAgAQAVAAcJVwoEHwAgAQAUAAUJkQxyNADoAAAAAA==.Shamminator:BAAALgADCgMJAwAAAA==.Shamorex:BAABLgAECn8jAAIVAAcJYhaQFQBpAQAVAAcJYhaQFQBpAQAAAA==.Sharkbones:BAAALgAECgEJAQAAAA==.Shatter:BAAALgAECgcJCgAAAA==.Shax:BAAALgAECgUJBQABLgAECgcJGAAdAJgjAA==.Shiftyy:BAAALgAECgUJBgAAAA==.Shogun:BAAALgADCgQJCAAAAA==.Shteph:BAAALgADCgcJDQAAAA==.Shîftfaced:BAAALgAECgIJAgAAAA==.',
Si='Siaerosia:BAAALgADCgEJAQAAAA==.',
Sk='Skaarr:BAABLgAECn8VAAISAAgJ3QgtHQBHAQASAAgJ3QgtHQBHAQAAAA==.',
Sl='Slayn:BAAALgAECgUJDAAAAA==.Slowhealsboi:BAAALgAECgQJBAAAAA==.Slushpuppie:BAAALgADCgYJBgAAAA==.Slyrak:BAABLgAECn8cAAMKAAcJuhcxDgD3AQAKAAcJuhcxDgD3AQAoAAMJnwiXGgBmAAAAAA==.',
Sm='Smithbruh:BAAALgAECgMJAwABLgAECggJIAAlAL0hAA==.Smitus:BAAALgAECgIJAwAAAA==.Smokescale:BAAALgADCgcJCAAAAA==.',
Sn='Snackie:BAAALgAECgcJDQAAAA==.Snotpig:BAAALgAECggJBwAAAA==.',
So='Solarious:BAAALgAECgEJAQAAAA==.Sorscrasus:BAAALgADCgUJCAAAAA==.Soulcolektor:BAAALgADCgcJCAAAAA==.Souled:BAAALgADCgYJBgAAAA==.',
Sp='Sparroh:BAAALgADCgEJAQAAAA==.Spikedriver:BAABLgAECn8ZAAIOAAgJhhEIIAChAQAOAAgJhhEIIAChAQAAAA==.Spradwurd:BAAALgAECgUJCAAAAA==.',
St='Stantonio:BAAALgAECgcJCwAAAA==.Stariane:BAABLgAECn8bAAIGAAgJmx3PAwBUAgAGAAgJmx3PAwBUAgAAAA==.Startaster:BAAALgAECgYJBwAAAA==.Starvoid:BAAALgAECgEJAQAAAA==.Steaktartare:BAAALgAECgYJCwAAAA==.Steelfist:BAAALgAECgYJCgAAAA==.Steelpunch:BAAALgAECgUJCAAAAA==.Steelwill:BAAALgAECgIJAgAAAA==.Stonii:BAAALgADCgUJBQAAAA==.Stony:BAABLgAECn8YAAIOAAYJ0h9VFwDYAQAOAAYJ0h9VFwDYAQAAAA==.Stonyy:BAAALgAECgEJAQAAAA==.Strelizia:BAAALgAECgIJAgAAAA==.Stressful:BAAALgADCgQJBAAAAA==.',
Su='Suetekh:BAAALgADCgUJBQAAAA==.Sukidaiyo:BAAALgAECgcJCAAAAA==.Summers:BAAALgAECgMJBQAAAA==.Sumonmyface:BAAALgAECgQJBgABLgAECggJHAANAHYSAA==.Sunshield:BAAALgADCgkJCwAAAA==.Superillbomb:BAAALgADCgcJCAAAAA==.Suraug:BAAALgADCgcJBwAAAA==.Suzakku:BAAALgAECgEJAQAAAA==.',
Sw='Swampraught:BAABLgAECn8WAAMMAAYJQxf2MABnAQAMAAYJQxf2MABnAQAdAAEJtA2ecAA1AAAAAA==.',
Sy='Syd:BAAALgADCgYJBgAAAA==.Syletage:BAAALgAECgIJAgAAAA==.Synrae:BAAALgAECgYJBgAAAA==.Syral:BAAALgAECgMJBAAAAA==.Syrion:BAAALgAECgQJBAAAAA==.Sythrane:BAAALgADCgcJBwAAAA==.',
Ta='Taarii:BAAALgADCggJCAAAAA==.Talisoudwave:BAAALgAECgMJBwABLgAECggJFAAIACsjAA==.Talomeo:BAAALgAECgIJAgAAAA==.Taradan:BAAALgAECgEJAQAAAA==.Taraxus:BAAALgADCgUJBQAAAA==.Tateraider:BAABLgAECn8jAAIaAAgJeR73AgBqAgAaAAgJeR73AgBqAgAAAA==.Taurnator:BAAALgAECgIJAwAAAA==.Taylorswift:BAAALgAECgMJBgAAAA==.Tayven:BAAALgADCgEJAQAAAA==.',
Te='Telain:BAABLgAECn8hAAMeAAgJwhJaDgD2AQAeAAgJwhJaDgD2AQAjAAQJJQq44QDKAAAAAA==.Tensuki:BAAALgAECgEJAQAAAA==.Teslah:BAAALgADCgQJBAAAAA==.',
Th='Thakilla:BAABLgAECn8iAAIZAAgJ+xKLDADEAQAZAAgJ+xKLDADEAQAAAA==.Thanosonmage:BAAALgADCgcJBwAAAA==.Thavik:BAAALgADCgEJAwAAAA==.Theolodin:BAAALgAECgMJAwAAAA==.Thordrik:BAAALgAECgEJAQAAAA==.Thorix:BAAALgAECgcJDQAAAA==.Thotmir:BAAALgAECgMJAwAAAA==.Thícc:BAAALgADCgkJCgAAAA==.',
Ti='Tikibiki:BAAALgADCgMJAwAAAA==.Timbereses:BAAALgADCgUJBQAAAA==.Timberreaper:BAAALgAECgIJAgAAAA==.Tinyz:BAAALgAECgUJDQAAAA==.',
To='Tolua:BAAALgAECgUJCAAAAA==.Tonata:BAAALgAECggJDgAAAA==.Tonythetiger:BAAALgAECgEJAQABLgAECgcJFwAYABsZAA==.Tootsie:BAAALgADCgYJEAAAAA==.',
Tr='Trenton:BAAALgADCgUJBwAAAA==.Trexlot:BAAALgAECgIJAgAAAA==.Trinjal:BAABLgAECn8VAAIkAAcJ2BqqDQDLAQAkAAcJ2BqqDQDLAQAAAA==.Trishift:BAAALgAECgMJAwAAAA==.Trueshru:BAAALgAECgIJAwAAAA==.',
Tu='Tubular:BAAALgAECgMJBQAAAA==.Tuskadin:BAABLgAECn8mAAIjAAgJsCKuGwDEAgAjAAgJsCKuGwDEAgAAAA==.',
Ty='Tyjan:BAAALgAECgUJDAAAAA==.Tyrana:BAAALgAECgMJAwAAAA==.Tyriq:BAAALgADCgYJBgAAAA==.',
Un='Unclothed:BAAALgAECgYJDgAAAA==.Unicorn:BAAALgADCggJCAAAAA==.Untòld:BAAALgADCggJCAABLgAECgcJFQAQAGUNAA==.',
Va='Valentine:BAAALgADCgIJAgAAAA==.Valitymage:BAAALgADCgEJAQAAAA==.Varyusha:BAAALgAECgMJBAAAAA==.',
Ve='Velene:BAAALgADCgEJAQABLgAECggJJAAQADEYAA==.Venzallow:BAAALgAECgUJBwAAAA==.Veralynn:BAAALgADCgcJBwAAAA==.Veravibes:BAAALgAECgQJCAAAAA==.Vermagnus:BAAALgAECgcJEwAAAA==.Vespor:BAABLgAECn8XAAIIAAYJGB0HFQDcAQAIAAYJGB0HFQDcAQAAAA==.',
Vi='Viktorya:BAABLgAECn8eAAIoAAcJDBeWFgDlAQAoAAcJDBeWFgDlAQAAAA==.Vilelyn:BAAALgAECgYJCgABLgAECgYJDwAFAAAAAA==.Viloria:BAABLgAECn8WAAIcAAYJXgwwEAC2AAAcAAYJXgwwEAC2AAAAAA==.Vincent:BAAALgADCgkJCgAAAA==.Virrard:BAABLgAECn8eAAMOAAcJJxyXFQDlAQAOAAcJJxyXFQDlAQADAAIJYA+DdQBoAAAAAA==.Vitalyellow:BAAALgADCgYJBgAAAA==.',
Vl='Vladimor:BAAALgAECgYJEgAAAA==.Vladimyrr:BAAALgAECgcJDwAAAA==.',
Vo='Vodan:BAAALgADCgEJAQAAAA==.Voidplague:BAAALgAECgUJCAAAAA==.Voidscarred:BAAALgAECgQJDgAAAA==.Vozrezz:BAAALgAECgcJEwAAAA==.',
Vu='Vualake:BAAALgADCgYJCgAAAA==.',
Vy='Vyridian:BAAALgAECgQJAwABLgAECgYJEwAFAAAAAA==.',
['Vë']='Vëda:BAABLgAECn8aAAImAAgJAgxfFgBbAQAmAAgJAgxfFgBbAQAAAA==.',
Wa='Wardragon:BAAALgADCgcJCwAAAA==.Wasical:BAAALgAECgMJAgAAAA==.',
Wh='Wheaties:BAAALgAECgUJBQABLgAECgcJFwAYABsZAA==.',
Wi='Wicker:BAABLgAECn8fAAIcAAgJriKMAQB+AgAcAAgJriKMAQB+AgAAAA==.Wickievoker:BAAALgADCgkJCQABLgAECggJHwAcAK4iAA==.Wintin:BAAALgAECgEJAgAAAA==.Wiskey:BAAALgADCgYJBgAAAA==.',
Wo='Wolford:BAABLgAECn8WAAIIAAYJNh2sFADgAQAIAAYJNh2sFADgAQAAAA==.Woogie:BAAALgADCgYJCgAAAA==.',
Wr='Wras:BAAALgAECgYJDwAAAA==.Wretched:BAAALgAECgcJBQAAAA==.',
Wy='Wysstical:BAAALgAECgcJBwABLgAFFAUJEwABAO0eAA==.',
['Wò']='Wòbbles:BAAALgAECgQJCQAAAA==.',
Xa='Xandos:BAAALgADCgEJAQAAAA==.Xandrah:BAAALgAECgQJCQAAAA==.Xanslash:BAABLgAECn8aAAIHAAgJER8fEQDlAQAHAAgJER8fEQDlAQAAAA==.Xari:BAACLgAFFH8RAAIQAAUJ8BWdGgBfAQAQAAUJ8BWdGgBfAQAuAAQKfyUAAhAACQluIgcSADsDABAACQluIgcSADsDAAAA.',
Xh='Xhalo:BAAALgADCggJCAAAAA==.',
Xi='Xiansai:BAABLgAECn8aAAICAAgJvhWvDAC2AQACAAgJvhWvDAC2AQAAAA==.',
Ya='Yappey:BAABLgAECn8XAAIlAAYJICNiCwDTAQAlAAYJICNiCwDTAQAAAA==.',
Ye='Yehni:BAABLgAECn8xAAImAAkJEyRZAACRAwAmAAkJEyRZAACRAwAAAA==.',
Za='Zaesha:BAAALgADCgYJCAAAAA==.Zalarii:BAAALgADCgEJAgAAAA==.Zarox:BAAALgAECggJEgAAAA==.',
Ze='Zeroelement:BAABLgAECn8VAAIeAAgJkhtbGgB6AQAeAAgJkhtbGgB6AQAAAA==.',
Zi='Zimgir:BAAALgADCgEJAQAAAA==.',
Zo='Zombiehippo:BAABLgAECn8gAAIQAAgJPRmYIADqAQAQAAgJPRmYIADqAQAAAA==.Zorcons:BAAALgAECgEJAQAAAA==.',
Zu='Zuuzuu:BAAALgADCgEJAQAAAA==.',
['Áu']='Áutarch:BAAALgAECgYJDAAAAA==.',
['Èl']='Èlty:BAAALgAECgMJAwAAAA==.',
['Ðe']='Ðemøn:BAAALgAECgEJAQAAAA==.',
['Ðr']='Ðrexy:BAAALgADCgUJBQAAAA==.',
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
