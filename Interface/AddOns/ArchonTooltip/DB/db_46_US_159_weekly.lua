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

local lookup = {'Shaman-Enhancement','Priest-Shadow','Hunter-Marksmanship','Monk-Windwalker','Unknown-Unknown','DeathKnight-Blood','Warrior-Fury','Evoker-Preservation','DemonHunter-Havoc','DemonHunter-Devourer','Monk-Mistweaver','Druid-Restoration','Evoker-Augmentation','Evoker-Devastation','Priest-Discipline','Hunter-BeastMastery','Warlock-Demonology','Hunter-Survival','Rogue-Subtlety','Mage-Frost','DeathKnight-Unholy','Paladin-Retribution','Mage-Arcane','Paladin-Protection','Shaman-Restoration','Druid-Guardian','Shaman-Elemental','Mage-Fire','Warrior-Arms','Druid-Balance','Warrior-Protection','Druid-Feral','Warlock-Affliction','Warlock-Destruction','Paladin-Holy','Rogue-Outlaw','Rogue-Assassination','DeathKnight-Frost','Monk-Brewmaster','Priest-Holy',}
local provider = {region='US',realm='Moonrunner',name='US',type='weekly',zone=46,date='2026-05-08',data={Ac='Acense:BAAALgAECgYJDAAAAA==.Acewing:BAAALgADCgkJCgAAAA==.Acidlock:BAAALgAECgEJAgAAAA==.Acidpriest:BAAALgAECgcJDAAAAA==.Acidshaman:BAAALgADCgYJBwAAAA==.',
Ad='Adacey:BAAALgAECgUJBgAAAA==.Adragon:BAAALgAECgcJDQAAAA==.',
Ae='Aedryll:BAAALgAECgYJDQAAAA==.Aeriden:BAAALgAECgEJAQAAAA==.Aesuga:BAABLgAECn8xAAIBAAkJkSGSAAAiAwABAAkJkSGSAAAiAwAAAA==.Aethelflaed:BAABLgAECn8ZAAICAAYJ4ht9FgCLAQACAAYJ4ht9FgCLAQAAAA==.',
Ag='Agnolotti:BAAALgAECgUJCAAAAA==.',
Ai='Aimedjupiter:BAAALgAECgYJEQABLgAFFAMJBgADAL0ZAA==.Air:BAAALgADCgcJBwABLgAECggJGAAEAPsZAA==.Airlyn:BAAALgAECgYJEQAAAA==.Aisen:BAAALgADCgEJAQABLgAECgEJAQAFAAAAAA==.',
Ak='Aktras:BAAALgAECgUJDwAAAA==.',
Al='Alaunu:BAAALgADCgkJBgAAAA==.Aleas:BAAALgAECgQJBAAAAA==.Aliciab:BAAALgADCgYJCgAAAA==.Alkaid:BAAALgAECgEJAQAAAA==.Alndvia:BAAALgAECgYJCgAAAA==.Alponkster:BAAALgADCggJEwAAAA==.Alunia:BAAALgAECgIJBAAAAA==.Alytheal:BAAALgAECgEJAQABLgAECgkJHAAGAHoZAA==.',
Am='Americow:BAAALgAECgEJAQAAAA==.',
An='Anarky:BAABLgAECn8XAAIHAAcJhALLPwDBAAAHAAcJhALLPwDBAAAAAA==.Andarnah:BAAALgADCgQJBAAAAA==.Annunaki:BAAALgAECgIJAwAAAA==.Anthrfinpete:BAAALgAECgIJBwABLgAECgcJFwAIABIXAA==.Anze:BAAALgAECgIJAgAAAA==.',
Ar='Arathenes:BAAALgADCgcJCQAAAA==.Archae:BAAALgADCgYJCwAAAA==.Archdemon:BAAALgAFFAEJAQAAAA==.Ariannette:BAAALgAECgMJAwAAAA==.Arilyn:BAAALgADCgMJAwAAAA==.Arkhanx:BAAALgAECgUJCwAAAA==.Artemisia:BAAALgADCgkJHwAAAA==.Artichoke:BAABLgAECn8aAAMJAAgJZQ/zKwBpAQAJAAYJIxLzKwBpAQAKAAUJSQdueQClAAAAAA==.',
As='Ashamane:BAAALgAECgIJAgABLgAECgUJDAAFAAAAAA==.Ashanara:BAAALgADCgEJAQABLgAECgcJIAALANQQAA==.Ashy:BAAALgADCgUJBQAAAA==.Astrov:BAAALgAFFAEJAQAAAA==.',
At='Athera:BAAALgADCggJCAAAAA==.',
Au='Auani:BAABLgAECn8sAAIMAAkJhCNjAQCSAwAMAAkJhCNjAQCSAwAAAA==.Augtistic:BAABLgAECn8yAAMNAAkJ2RwYBADCAgANAAkJ2RwYBADCAgAOAAMJwRfSKwC+AAAAAA==.Aurani:BAAALgAECgEJAQAAAA==.',
Ay='Ayanna:BAAALgADCgkJFQAAAA==.',
Az='Azale:BAAALgAECgMJAwAAAA==.Azulagos:BAAALgADCgYJBgAAAA==.Azzeus:BAABLgAECn8YAAMCAAgJKhlSCgAfAgACAAgJKhlSCgAfAgAPAAEJmxMcVwAzAAAAAA==.',
Ba='Babyrinsjr:BAABLgAECn8VAAIQAAYJohX2PABaAQAQAAYJohX2PABaAQAAAA==.Baeyn:BAAALgAECgcJCwABLgAFFAMJBQARAA4VAA==.Bagel:BAABLgAECn8gAAQSAAgJyBpNDwC0AQASAAcJCRxNDwC0AQADAAUJARclOgB4AQAQAAYJ/QxTVQBoAQABLgAFFAUJFQABAN0fAA==.Baile:BAAALgAECgEJAQAAAA==.Bakon:BAAALgAECgUJDAAAAA==.Balin:BAAALgADCgYJDgAAAA==.Ballerin:BAAALgADCggJDwABLgAECgYJDQAFAAAAAA==.Barrada:BAABLgAECn8XAAIQAAcJcAwJPABdAQAQAAcJcAwJPABdAQAAAA==.Barricay:BAAALgAECgYJBwAAAA==.Bathroy:BAAALgADCgIJAgAAAA==.',
Be='Bearcane:BAAALgADCgUJBQABLgAFFAMJBwAKAKALAA==.Beardheals:BAAALgADCgQJBAAAAA==.Beardàddy:BAAALgAECgQJBQAAAA==.Bellamira:BAAALgADCgIJAgAAAA==.Benjarrey:BAAALgAECgUJBgAAAA==.Berea:BAAALgAECgYJDQAAAA==.',
Bi='Bigmeatyclaw:BAAALgAECgEJAwAAAA==.Billywitchdr:BAAALgADCgEJAQAAAA==.',
Bl='Blankdemonic:BAAALgAECgEJAQAAAA==.Bleedblue:BAABLgAECn8mAAITAAgJuBmwBgBEAgATAAgJuBmwBgBEAgAAAA==.Blueballmonk:BAAALgAECgUJCQAAAA==.Bluerare:BAABLgAECn8rAAIUAAgJ+xisJQAOAgAUAAgJ+xisJQAOAgAAAA==.',
Bo='Bobsgrundle:BAAALgAECgQJBAAAAA==.Bowlinna:BAAALgAECgQJBwAAAA==.',
Br='Brewrosia:BAAALgAECgYJCgAAAA==.Briiki:BAAALgAECgEJAQAAAA==.Brinnohms:BAAALgAECgEJAQAAAA==.Broadsnatl:BAAALgADCgEJAQAAAA==.Brunnhild:BAAALgADCgkJCQAAAA==.Bryxi:BAAALgAECgcJBwABLgAECggJGwAVAJwXAA==.Brünhilde:BAABLgAECn8jAAIPAAgJSRNMEQDCAQAPAAgJSRNMEQDCAQAAAA==.',
Bs='Bstbll:BAACLgAFFH8TAAIMAAYJLBK5CACuAQAMAAYJLBK5CACuAQAuAAQKfxYAAgwACQmUHv0JAPQCAAwACQmUHv0JAPQCAAAA.Bstwaves:BAAALgAECgQJBQAAAA==.',
Bu='Bubbleban:BAAALgADCgUJBQAAAA==.Bungxi:BAAALgADCgUJBgABLgAECggJGwAVAJwXAA==.Buraddo:BAAALgAECgEJAQABLgAECgcJFgAWAEoZAA==.Burrata:BAAALgADCgkJCQAAAA==.Buttsnacks:BAABLgAECn8gAAIHAAkJjyB6AgD2AgAHAAkJjyB6AgD2AgAAAA==.',
Ca='Cairebear:BAAALgAECgMJAwAAAA==.Callistrah:BAABLgAECn8YAAMXAAgJSxLXAgClAQAXAAcJ3BTXAgClAQAUAAIJXQTs3QBXAAAAAA==.Caltaa:BAABLgAECn8zAAIYAAkJdyLHAAD/AgAYAAkJdyLHAAD/AgAAAA==.Camael:BAAALgAECgUJCQAAAA==.Canarah:BAAALgADCgUJBQABLgAFFAMJCQAZAJ0SAA==.Canverian:BAABLgAECn8VAAIaAAYJ3Bn5CgBoAQAaAAYJ3Bn5CgBoAQAAAA==.Carmedic:BAAALgADCgcJDQAAAA==.',
Ce='Celexa:BAAALgAECgQJBQABLgAECgQJEQAFAAAAAA==.Celtmon:BAAALgADCgIJAwAAAA==.',
Ch='Cha:BAAALgAECgEJAQAAAA==.Chapi:BAAALgAECgYJCQAAAA==.Chasseurfool:BAAALgAECgUJEAAAAA==.Chat:BAACLgAFFH8PAAIbAAQJQRoeCwBQAQAbAAQJQRoeCwBQAQAuAAQKfycAAhsACQl9GWkSAI8CABsACQl9GWkSAI8CAAAA.Chewi:BAAALgADCgEJAQAAAA==.Chezaro:BAAALgAECgUJBgAAAA==.Chickenlitle:BAAALgADCgUJBQAAAA==.Chickenwing:BAABLgAECn8kAAIcAAgJCB+8AABxAgAcAAgJCB+8AABxAgAAAA==.Chilin:BAAALgADCgMJAwABLgAECgMJAwAFAAAAAA==.Chilinevoke:BAAALgAECgMJAwAAAA==.Christano:BAABLgAECn8VAAMYAAYJOxltEQAnAQAWAAYJ4RJohgBtAQAYAAQJoxttEQAnAQAAAA==.Christhecold:BAABLgAECn8wAAMdAAgJ/xpeCgChAQAHAAYJRBYTOQDCAQAdAAYJ2BdeCgChAQAAAA==.Chrollo:BAAALgAECgUJCgAAAA==.Chronoknight:BAAALgADCgkJCQAAAA==.Chronson:BAAALgAECgEJAQAAAA==.Chunt:BAAALgAECgQJCQAAAA==.',
Cl='Clamscasino:BAAALgADCgIJAgABLgAECgcJEgAFAAAAAA==.Clarke:BAAALgADCgMJAwAAAA==.Cloudcrack:BAACLgAFFH8VAAIbAAUJDhpQCwBOAQAbAAUJDhpQCwBOAQAuAAQKfyEAAhsACQmQHf0KAOcCABsACQmQHf0KAOcCAAAA.Clynt:BAAALgADCgIJAgAAAA==.',
Co='Cocoapuffs:BAAALgADCgIJAgABLgAECggJHwAGAKIcAA==.Cocotaso:BAAALgAECgIJAwABLgAFFAIJBQAYAOQMAA==.Codemon:BAABLgAECn8dAAMOAAcJBRP0BgBPAQAOAAYJSRb0BgBPAQANAAcJqAfYKgAAAQAAAA==.Coldfusion:BAAALgADCgMJBAAAAA==.Condemn:BAAALgADCgEJAgAAAA==.Condiments:BAAALgAECgEJAgAAAA==.Cortar:BAAALgAECgkJCAAAAA==.',
Cp='Cptcharis:BAAALgADCgYJBgAAAA==.',
Cy='Cylrhea:BAABLgAECn8aAAIMAAgJESWZAgBYAwAMAAgJESWZAgBYAwAAAA==.Cyntrill:BAAALgAECgQJCAAAAA==.',
Da='Dadderz:BAAALgADCgkJEAAAAA==.Daddydruid:BAAALgAECgQJBQAAAA==.Dahunter:BAAALgAECgYJCAAAAA==.Dajoel:BAAALgAECgYJDQAAAA==.Dakinna:BAAALgADCgMJAwAAAA==.Dakotawolfe:BAAALgADCgUJBQAAAA==.Dalacia:BAABLgAECn8UAAIZAAgJuhJVOgCYAQAZAAgJuhJVOgCYAQAAAA==.Dannyrojas:BAAALgAECgEJAgAAAA==.Darkforceray:BAAALgADCgEJAQAAAA==.Darknature:BAABLgAECn8qAAMMAAgJohOgIwCrAQAMAAgJohOgIwCrAQAeAAcJXw48JQASAQAAAA==.Darkodin:BAABLgAECn8dAAIVAAcJ5wmHVwA4AQAVAAcJ5wmHVwA4AQAAAA==.Darkomen:BAAALgADCgcJGQABLgAECgcJIgAVALgNAA==.Darkvlad:BAABLgAECn8iAAIVAAcJuA1nTwBOAQAVAAcJuA1nTwBOAQAAAA==.Datnagadrake:BAACLgAFFH8LAAMHAAMJdhIeGQDqAAAHAAMJAREeGQDqAAAfAAIJXxUSCwCWAAAuAAQKfzEAAwcACAlmIrgFAJgCAAcACAlmIrgFAJgCAB8AAQmJIW8/AFUAAAAA.Davere:BAAALgADCgEJAQAAAA==.Dawinchy:BAACLgAFFH8GAAIMAAMJ+wXSKgCiAAAMAAMJ+wXSKgCiAAAuAAQKfzIABAwACQmIFEQ0ANcBAAwACQmIFEQ0ANcBACAABwluC9sMAEoBAB4AAQmnBa9hACQAAAAA.',
Dc='Dchalla:BAAALgADCgcJDQAAAA==.',
De='Deadlypsycho:BAAALgAECgYJEgAAAA==.Deadmanrise:BAAALgADCgUJBQAAAA==.Deathawakens:BAAALgAFFAIJAgAAAA==.Deathlyill:BAAALgAECgYJEQAAAA==.Deathtouch:BAAALgADCgcJDAAAAA==.Decembër:BAABLgAECn8kAAIUAAgJKgdAXwBUAQAUAAgJKgdAXwBUAQAAAA==.Decimious:BAAALgAECgQJBwAAAA==.Dekutree:BAABLgAECn8XAAMaAAgJ9wgXFwCrAAAaAAcJ2AkXFwCrAAAgAAEJsQPlKwApAAAAAA==.Dellistia:BAAALgAECgMJCAAAAA==.Delvan:BAAALgAECgIJAgAAAA==.Demiglace:BAAALgAECgYJDAAAAA==.Demonkilla:BAAALgAECgYJDgAAAA==.Denadan:BAAALgAECgEJAQABLgAECggJIgAhAGQKAA==.Desdamona:BAABLgAECn8YAAIQAAcJ5wRSVwAJAQAQAAcJ5wRSVwAJAQAAAA==.Destrodeath:BAAALgAECgcJBwAAAA==.Destrodemon:BAABLgAECn8jAAIKAAgJARJ6MgBsAQAKAAgJARJ6MgBsAQAAAA==.Deviltango:BAAALgAECgQJBAAAAA==.Devorick:BAABLgAECn8lAAMRAAkJ5hVnFwAnAgARAAkJ5hVnFwAnAgAiAAIJQxClUQB5AAAAAA==.Deztaknee:BAAALgADCgUJBQAAAA==.',
Di='Diadem:BAAALgAECgMJBAABLgAFFAMJBQARAA4VAA==.Diathian:BAAALgAECgUJBwABLgAFFAUJFgAUABUUAA==.Diaval:BAAALgAECgYJDwAAAA==.Dih:BAAALgADCgkJFQABLgAECggJIwASAHQSAA==.Dihlngthepal:BAAALgAECgEJAQAAAA==.Dirtyzealot:BAAALgADCgkJFwAAAA==.Disenchanted:BAAALgAECgYJBgABLgAECgcJGgANAM0bAA==.Divineknight:BAAALgADCgkJFQAAAA==.Diyiya:BAAALgAECgYJCwAAAA==.',
Do='Doorki:BAAALgAFFAIJBAAAAA==.Doubleott:BAAALgAECgEJAQAAAA==.',
Dr='Drael:BAAALgADCgkJKAAAAA==.Dragonayre:BAAALgAECgUJCQABLgAFFAMJBQARAA4VAA==.Draickin:BAABLgAECn8eAAIjAAcJMhMtGwCwAQAjAAcJMhMtGwCwAQAAAA==.Drekle:BAAALgAECgcJBwAAAA==.Drelian:BAAALgAECgQJBgAAAA==.Drenzel:BAAALgADCgYJCQAAAA==.Drevy:BAABLgAECn8WAAQTAAcJHhafEwB2AQATAAcJHhafEwB2AQAkAAMJOgiRDABdAAAlAAEJAAA0HgAAAAAAAA==.Drewsguy:BAAALgADCgkJJAAAAA==.Drexchan:BAAALgAECgYJDwAAAA==.Drexen:BAAALgADCgQJBAAAAA==.Drexy:BAAALgAECgEJAQAAAA==.Dropdahammer:BAAALgADCgUJBQAAAA==.Drumma:BAAALgAECgMJBAAAAA==.Drumroleplz:BAABLgAECn8aAAMNAAcJzRuFFgCOAQAOAAUJWSCTEwCrAQANAAYJ/xWFFgCOAQAAAA==.',
Ds='Dsanatrestk:BAABLgAECn8oAAMVAAkJ2CRMBAAfAwAVAAkJ2CRMBAAfAwAGAAcJ1RpXEAAFAgAAAA==.',
['Dà']='Dàddybear:BAAALgAECgUJEAAAAA==.',
Ea='Earthsangel:BAAALgAECgcJCAAAAA==.',
Ec='Eclair:BAABLgAFFH8FAAIYAAMJ8g/hBQC0AAAYAAMJ8g/hBQC0AAAAAA==.',
Ed='Edralyia:BAAALgAECgMJCAAAAA==.',
Ei='Eilaurosa:BAABLgAECn8wAAIlAAkJLxTQAgAfAgAlAAkJLxTQAgAfAgAAAA==.',
El='Eldrinne:BAAALgAECgUJEAAAAA==.Elftuah:BAAALgADCggJCAAAAA==.Elfö:BAABLgAECn8VAAIQAAkJThVbGgAAAgAQAAkJThVbGgAAAgAAAA==.Elizawrath:BAABLgAECn8mAAMYAAgJBh9sBQCgAgAYAAgJBh9sBQCgAgAjAAUJlBHdWgAQAQAAAA==.Elkuco:BAAALgAECgIJAgAAAA==.Elthiss:BAABLgAECn8kAAIaAAgJ6BLuCgBpAQAaAAgJ6BLuCgBpAQAAAA==.',
Em='Emariel:BAAALgAECgEJAQAAAA==.',
En='Enchäntress:BAABLgAECn8YAAMRAAgJTwznPQBxAQARAAgJTwznPQBxAQAhAAEJAACCNwAjAAAAAA==.Enfer:BAAALgADCgYJCAABLgAFFAQJDwAbAEEaAA==.Enogg:BAAALgAECgQJBQAAAA==.Envi:BAABLgAECn8tAAIUAAkJexfRFgBkAgAUAAkJexfRFgBkAgAAAA==.',
Ep='Ephraìm:BAAALgADCgQJCAAAAA==.',
Er='Erianthe:BAABLgAECn8qAAIVAAkJfAkLNgChAQAVAAkJfAkLNgChAQAAAA==.Erophien:BAAALgADCgkJGgAAAA==.Erovael:BAAALgADCgQJBAABLgADCgkJGgAFAAAAAA==.Erovynael:BAAALgAECgUJDgAAAA==.',
Ev='Eversong:BAAALgAECgYJDwAAAA==.Evhi:BAAALgAECgYJCQAAAA==.',
Ex='Exmar:BAAALgAECgMJAwAAAA==.',
Fa='Faewhisker:BAAALgADCgcJEQAAAA==.Falnor:BAAALgADCgkJDAABLgAECgkJJgACAHsaAA==.Famine:BAABLgAECn8iAAMVAAgJUx3sMQBwAgAVAAgJUx3sMQBwAgAmAAEJAAC/GgAAAAAAAA==.Fancyfeet:BAAALgAECgUJBQABLgAFFAUJEAATAIIXAA==.',
Fc='Fckmalfurion:BAAALgADCgkJCQABLgAECggJIwASAHQSAA==.',
Fe='Fearios:BAABLgAECn8fAAIGAAgJohwnBgA9AgAGAAgJohwnBgA9AgAAAA==.Febronia:BAAALgAECgUJBQAAAA==.Felbeast:BAAALgAECgYJBQAAAA==.Felbound:BAAALgAECgEJAQAAAA==.Felltheburn:BAAALgADCgEJAQAAAA==.',
Fi='Figmênt:BAAALgAECgUJDgABLgAECgcJEgAFAAAAAA==.Finatic:BAAALgAECgMJAwAAAA==.Finneous:BAAALgAECgQJCQAAAA==.Fireproof:BAABLgAECn8bAAMYAAcJjiKNCABPAgAYAAcJOiCNCABPAgAWAAcJyBv5OQA7AgAAAA==.Fistedwaffle:BAAALgAECgEJAQABLgAFFAIJBQAYAOQMAA==.Fistopher:BAAALgAECgEJAQAAAA==.',
Fj='Fjorskin:BAAALgAECgQJBAAAAA==.',
Fl='Flairdragin:BAAALgAECgYJDQAAAA==.Flare:BAAALgAECggJEgAAAA==.',
Fo='Forix:BAAALgADCggJDAAAAA==.',
Fr='Fries:BAAALgADCggJCAAAAA==.Frosttbyte:BAABLgAECn8dAAIUAAkJbxxEDgCrAgAUAAkJbxxEDgCrAgAAAA==.Frostytute:BAAALgADCgcJDwAAAA==.Frozenwitch:BAAALgADCgUJBQAAAA==.',
Fu='Funsies:BAAALgADCgEJAQAAAA==.',
Fy='Fyrrstorm:BAAALgAECgIJAgAAAA==.',
['Fë']='Fëiróx:BAAALgADCgYJBgAAAA==.',
Ga='Gallum:BAAALgADCgEJAQAAAA==.Gamuza:BAAALgAECgQJBAAAAA==.',
Ge='Getzi:BAABLgAECn8aAAIWAAgJsyL5FQDlAgAWAAgJsyL5FQDlAgAAAA==.',
Gh='Ghavinflip:BAAALgAECgcJEgAAAA==.',
Gi='Gil:BAABLgAECn8oAAIKAAkJLiFzBADtAgAKAAkJLiFzBADtAgAAAA==.Gimlita:BAAALgAECgIJAgABLgAECggJGwAVAJwXAA==.Gindraxx:BAAALgADCgEJAQAAAA==.',
Gl='Glocket:BAAALgADCgEJAQAAAA==.',
Go='Goatspace:BAAALgADCgcJDgABLgAECggJIgAhAGQKAA==.Goettel:BAAALgAECgUJBQAAAA==.Gogmazios:BAAALgADCgEJAQAAAA==.Gogofisco:BAAALgAECgEJAgAAAA==.Gongagà:BAAALgAECgYJDAAAAA==.Goodnoodle:BAAALgADCgEJAQAAAA==.Goyum:BAAALgAECgEJAQAAAA==.',
Gr='Grankino:BAABLgAECn8bAAIgAAcJbxeaBwC8AQAgAAcJbxeaBwC8AQAAAA==.Grapenuts:BAAALgADCgEJAQABLgAECggJHwAGAKIcAA==.Grayves:BAAALgAECgUJBAAAAA==.Greenthumbs:BAAALgAECgcJEQAAAA==.Greyhulk:BAAALgAECgYJEgAAAA==.Grinlock:BAAALgADCgEJAQAAAA==.',
Gu='Guldanshower:BAAALgADCgIJAgAAAA==.Gurni:BAAALgADCgYJCAAAAA==.Guthan:BAAALgAECgEJAQAAAA==.Guthild:BAAALgAECgIJAgAAAA==.',
Gw='Gwaelphypha:BAABLgAECn8bAAIVAAgJnBf1RAAmAgAVAAgJnBf1RAAmAgAAAA==.',
Ha='Hakarii:BAAALgADCgYJDAAAAA==.Halliax:BAAALgADCgYJBgABLgAFFAMJBQARAA4VAA==.Hamburglar:BAAALgADCgYJCAAAAA==.Hapkido:BAABLgAECn80AAMLAAkJkh8qAwAJAwALAAkJkh8qAwAJAwAEAAEJcgTPaQApAAAAAA==.Hardsus:BAAALgAECgQJAwAAAA==.Hawfmave:BAAALgAECgcJCwAAAA==.',
He='Heals:BAAALgAECgMJAwAAAA==.Healthpotion:BAAALgAECgMJAwAAAA==.Heartbroken:BAAALgAECgkJBwAAAA==.Hecate:BAABLgAECn8VAAIWAAcJ+wSldQABAQAWAAcJ+wSldQABAQAAAA==.Heidnik:BAAALgADCgQJBAAAAA==.Helvetica:BAAALgADCggJDwAAAA==.Heretic:BAAALgAECgUJDAAAAA==.',
Hi='Hillboy:BAAALgAECgYJBgAAAA==.Hippiehulk:BAAALgAECgEJAQAAAA==.',
Ho='Holydes:BAAALgADCgkJFwABLgAECgcJGAAQAOcEAA==.Holyfrejoles:BAAALgAECgkJAQAAAA==.Holyshrimp:BAABLgAECn8qAAICAAgJIhrxCwAGAgACAAgJIhrxCwAGAgAAAA==.Hordor:BAAALgAECgEJAQAAAA==.Hotndot:BAAALgADCgcJCgAAAA==.',
Hu='Hummakavulä:BAAALgAECgUJDAAAAA==.Hunkahunka:BAAALgAECgMJBAAAAA==.Huunaron:BAABLgAECn8YAAMjAAgJNhk3LwDGAQAjAAgJNhk3LwDGAQAWAAQJUwczlQDEAAAAAA==.',
Id='Idylwilde:BAAALgAECgUJCwAAAA==.',
Ie='Ienzo:BAAALgADCgUJBQAAAA==.',
If='Ifunny:BAAALgAECgcJCgAAAA==.',
Ih='Iheartoreos:BAABLgAECn8iAAMGAAYJfRHqGAADAQAGAAYJYRHqGAADAQAmAAQJLwnuDgCzAAAAAA==.',
Il='Ilovefuta:BAAALgAFFAEJAgAAAA==.',
In='Inferna:BAAALgADCgQJCAAAAA==.Infidelis:BAAALgAECgEJAQAAAA==.Ink:BAABLgAFFH8FAAIVAAMJfxbiOwClAAAVAAMJfxbiOwClAAAAAA==.Inmortuae:BAAALgAECgMJAwAAAA==.Instakill:BAAALgADCgYJCQAAAA==.Insulin:BAAALgADCgkJEgAAAA==.Invictae:BAAALgAECgcJEgAAAA==.',
Io='Iobo:BAACLgAFFH8OAAIKAAYJ3Rs3FwBNAQAKAAYJ3Rs3FwBNAQAuAAQKfxgAAgoACQl4Ig8HAFYDAAoACQl4Ig8HAFYDAAAA.',
Ir='Iradori:BAABLgAFFH8WAAIUAAUJFRR9GgBhAQAUAAUJFRR9GgBhAQAAAA==.Irønbane:BAAALgAECgEJAQAAAA==.',
Is='Iskandar:BAAALgAECgQJBwAAAA==.Isparian:BAABLgAECn8eAAMWAAcJ9RdaRgByAQAWAAYJPRlaRgByAQAjAAEJiwnQZgAsAAAAAA==.Issior:BAAALgAECgIJAgAAAA==.',
Ja='Jaegar:BAAALgADCgIJAgAAAA==.Jamal:BAAALgADCgkJGwAAAA==.Jarco:BAEBLgAFFH8IAAMQAAQJZhPFDQBiAQAQAAQJZhPFDQBiAQASAAEJigQpHQBMAAAAAA==.Jasmyn:BAAALgADCgEJAQAAAA==.Jasseca:BAAALgADCggJCAABLgAECggJGwAVAJwXAA==.Java:BAABLgAECn8VAAIRAAcJ/wvnTgA9AQARAAcJ/wvnTgA9AQAAAA==.',
Je='Jeandarc:BAAALgADCgkJCQAAAA==.',
Jo='Joedakilla:BAAALgAECgEJAQAAAA==.Jonorin:BAAALgADCgEJAQAAAA==.',
Js='Jshaman:BAAALgAECgYJEAAAAA==.',
Ju='Judoken:BAABLgAECn8VAAMTAAYJIAdqHwABAQATAAYJHAdqHwABAQAlAAUJUwLmFACsAAAAAA==.Jupiterr:BAABLgAFFH8GAAMDAAMJvRkrEwAKAQADAAMJvRkrEwAKAQAQAAEJGREAAAAAAAAAAA==.',
Ka='Kaadra:BAAALgAECgEJAQAAAA==.Kaelgen:BAAALgAECgMJAwAAAA==.Kaelkin:BAAALgAECgYJDQABLgAECggJGQAZALAYAA==.Kaelthlar:BAAALgAECgIJAwAAAA==.Kaelun:BAAALgAECgQJBgABLgAECggJGQAZALAYAA==.Kaelundrus:BAABLgAECn8ZAAMZAAgJsBhWRwBkAQAZAAYJLhdWRwBkAQABAAcJbA+5EQDkAAAAAA==.Kainis:BAAALgAECgQJCQAAAA==.Kairia:BAAALgADCgEJAQAAAA==.Kalvinakri:BAAALgADCgkJDgAAAA==.Karasana:BAAALgAECgQJBAAAAA==.Karmus:BAAALgAECgYJDAAAAA==.Kastaspella:BAABLgAECn8VAAIUAAcJdQ3iWgBfAQAUAAcJdQ3iWgBfAQAAAA==.Kau:BAAALgAECgUJCQAAAA==.Kawant:BAAALgAECgIJAwAAAA==.Kaylnee:BAAALgAECgYJEwAAAA==.',
Ke='Keadin:BAAALgAECgMJCAAAAA==.Kearra:BAAALgADCgkJCQAAAA==.Kehayne:BAAALgADCgQJBAAAAA==.Keilas:BAAALgAECgcJDgAAAA==.Kerro:BAAALgAECgIJAwAAAA==.Kerron:BAAALgADCgMJAwAAAA==.Keyes:BAACLgAFFH8aAAInAAcJQhiXAQD8AQAnAAcJQhiXAQD8AQAuAAQKfycAAicACQlhIfoCANUCACcACQlhIfoCANUCAAAA.Keylala:BAABLgAECn8VAAMiAAYJixFVCgAxAQAiAAYJixFVCgAxAQARAAIJTwR2vQBOAAAAAA==.',
Ki='Kiafera:BAAALgADCgMJAwAAAA==.Kickenmage:BAAALgAECgEJAQABLgAECgYJDwAFAAAAAA==.Kickentail:BAAALgAECgYJDwAAAA==.Kidx:BAAALgAECgMJAwAAAA==.Kirisham:BAAALgAECgQJBAAAAA==.Kirlia:BAAALgAECgMJBgAAAA==.Kishenia:BAAALgAECgIJAgAAAA==.',
Kl='Kleanx:BAAALgADCgQJBAAAAA==.Klymax:BAAALgADCgUJBQAAAA==.',
Ko='Kongor:BAABLgAECn8UAAIBAAgJyA/MCACWAQABAAgJyA/MCACWAQAAAA==.Korathazan:BAAALgADCgEJAQAAAA==.Korithelse:BAAALgAECgEJAQAAAA==.Korthea:BAAALgAECgIJAgAAAA==.',
Kr='Krispitreat:BAAALgAECgYJCwAAAA==.Kritnespears:BAAALgAECgcJDwAAAA==.Krobelus:BAABLgAECn8zAAMWAAkJYgu2PQCNAQAWAAkJYgu2PQCNAQAjAAYJVQXiZADoAAAAAA==.',
Kv='Kvedaheillr:BAAALgAECgMJAwAAAA==.Kvedaroðull:BAAALgADCgYJBwAAAA==.Kvedathulr:BAAALgADCgYJBgAAAA==.',
Ky='Kyluna:BAAALgAECgEJAQAAAA==.',
['Kè']='Kères:BAAALgAECgYJDQAAAA==.Kèrónos:BAAALgADCgkJKAAAAA==.',
['Kì']='Kìllstheweak:BAABLgAECn8oAAMmAAkJGRDtBACPAQAmAAkJPA/tBACPAQAGAAYJ3QwKJwAGAQAAAA==.',
La='Lauralai:BAAALgADCgcJCAAAAA==.Lavendra:BAAALgADCgcJDwAAAA==.Lawkz:BAAALgAECgcJCAAAAA==.Layliah:BAACLgAFFH8VAAIeAAUJBiPXBQCNAQAeAAUJBiPXBQCNAQAuAAQKfzgAAh4ACQkEJZ0AAGgDAB4ACQkEJZ0AAGgDAAAA.',
Le='Leafless:BAAALgAECgEJAQAAAA==.Leaftemplar:BAAALgADCgYJBgAAAA==.Leedragoon:BAAALgADCgMJAwAAAA==.Legaia:BAAALgADCgYJCQAAAA==.Legendknewl:BAAALgAECgIJAgAAAA==.Lemmesapthat:BAAALgADCgEJAQAAAA==.Leviathonian:BAAALgAECgEJAQAAAA==.',
Li='Lightseeker:BAAALgAECgEJAQAAAA==.Lillinna:BAAALgADCgQJBAAAAA==.Lisithen:BAAALgADCgEJAQAAAA==.Littlespoon:BAAALgAECgEJAQABLgAECgEJAwAFAAAAAA==.',
Lo='Loafai:BAABLgAECn8iAAQhAAgJZAo8BwA1AQAhAAcJGAo8BwA1AQAiAAYJ/gezDwDbAAARAAYJCQQQ1QCwAAAAAA==.Lockrocks:BAABLgAECn8YAAIRAAgJshaZIADtAQARAAgJshaZIADtAQAAAA==.Lorcán:BAAALgAECgMJCAAAAA==.Lormazlezrax:BAACLgAFFH8JAAIZAAMJnRI0JADEAAAZAAMJnRI0JADEAAAuAAQKfyEAAhkABwmtHxMZAE0CABkABwmtHxMZAE0CAAAA.',
Lu='Luis:BAAALgAECgQJBAAAAA==.Lumaron:BAAALgADCgEJAgAAAA==.Lunamizka:BAAALgADCgIJAgAAAA==.Lunella:BAAALgAECgQJBAABLgAECgUJDQAFAAAAAA==.Lunethira:BAAALgAECgUJDQAAAA==.Lustdeeznuts:BAABLgAECn8XAAIbAAYJjRsmGACPAQAbAAYJjRsmGACPAQAAAA==.',
Ly='Lylat:BAAALgAECgIJAgAAAA==.',
['Ló']='Lórdelrond:BAAALgADCgUJCgAAAA==.',
['Lú']='Lúpo:BAAALgAECgYJDQAAAA==.',
Ma='Machezemo:BAABLgAECn8eAAIUAAcJlSEBMgDYAQAUAAcJlSEBMgDYAQAAAA==.Madhatter:BAAALgAECgQJBgAAAA==.Mahalka:BAAALgAECgEJAQAAAA==.Maki:BAABLgAECn8cAAIoAAYJTiVmBwB9AgAoAAYJTiVmBwB9AgAAAA==.Malegar:BAAALgADCgkJIQAAAA==.Malendor:BAABLgAECn8nAAIEAAgJbyaRAQAZAwAEAAgJbyaRAQAZAwAAAA==.Mammajamma:BAAALgAECgEJAwAAAA==.Manbearcat:BAAALgAECgYJDQAAAA==.Marcydaghoul:BAAALgADCgUJBQAAAA==.Marivoker:BAAALgADCgkJJgABLgAECgYJCwAFAAAAAA==.Marsvolta:BAAALgADCgYJBgAAAA==.Maruxus:BAABLgAECn8lAAMlAAgJzBMNBQCzAQAlAAgJzBMNBQCzAQAkAAYJfg9LBgBhAQAAAA==.Marvilla:BAAALgAECggJEQAAAA==.Marwen:BAAALgADCgkJJAAAAA==.Mathbrew:BAEBLgAECn8gAAInAAgJyCHUBwBRAgAnAAgJyCHUBwBRAgAAAA==.Maulsin:BAAALgADCgYJCwAAAA==.',
Mc='Mcchicken:BAAALgADCgIJAgAAAA==.Mclardragos:BAABLgAECn8ZAAIIAAcJ9B5vBQBCAgAIAAcJ9B5vBQBCAgAAAA==.',
Me='Mehv:BAEALgAECgkJCwAAAQ==.Melindria:BAABLgAECn8aAAMeAAYJHw94PwA0AQAeAAYJHw94PwA0AQAaAAYJdwLaHwBeAAABLgAFFAEJAQAFAAAAAA==.Mendicine:BAAALgAECgYJDwAAAA==.Menmoe:BAAALgAECgEJAQAAAA==.',
Mf='Mfdoom:BAAALgAECgMJAwAAAA==.',
Mi='Miacyn:BAAALgAECgYJBgAAAA==.Miladybast:BAAALgAECgYJEgAAAA==.Mirra:BAABLgAECn8YAAIQAAgJEQphPwBQAQAQAAgJEQphPwBQAQAAAA==.Misha:BAAALgADCgUJBQAAAA==.Missdorei:BAAALgAECgMJAwAAAA==.',
Mo='Mogged:BAABLgAECn8cAAIUAAcJwCBmHABAAgAUAAcJwCBmHABAAgAAAA==.Mojocity:BAAALgADCgYJCwAAAA==.Molai:BAAALgAECgcJBAAAAA==.Monkdangit:BAAALgAECgYJCQAAAA==.Mordraidas:BAAALgADCgkJCQAAAA==.Morionso:BAABLgAECn8WAAIYAAcJIR24BwDXAQAYAAcJIR24BwDXAQAAAA==.Morphyrinsjr:BAAALgADCgcJCwABLgAECgYJFQAQAKIVAA==.Mortarion:BAABLgAECn8rAAIVAAkJUh5aCgC8AgAVAAkJUh5aCgC8AgAAAA==.Moxxulae:BAAALgADCgkJCAAAAA==.Moõn:BAABLgAECn8gAAINAAkJnwwkEwCwAQANAAkJnwwkEwCwAQAAAA==.',
Mu='Murcié:BAABLgAECn8lAAMKAAgJ8RWcOAASAgAKAAgJ0xWcOAASAgAJAAYJHwkLOgAZAQAAAA==.Murdiûs:BAABLgAECn8kAAILAAkJ7RszBwCIAgALAAkJ7RszBwCIAgAAAA==.',
My='Myaliki:BAAALgADCgcJBwABLgADCgkJGQAFAAAAAA==.Myregards:BAAALgADCgYJBwAAAA==.Myspaceshria:BAAALgAECgUJDgABLgAECggJGwAVAJwXAA==.Mythbruh:BAEALgAFFAEJAQABLgAECggJIAAnAMghAA==.Mythis:BAAALgAECgMJBAAAAA==.',
['Mó']='Mósh:BAAALgAECgYJBgAAAA==.',
Na='Nahane:BAAALgAECgEJAQAAAA==.Nahlur:BAAALgAECgMJAwAAAA==.Naoko:BAAALgAECgEJAgAAAA==.Nayrlock:BAACLgAFFH8FAAIRAAMJDhXVPADjAAARAAMJDhXVPADjAAAuAAQKfyUABBEACQkTIEcaALcCABEACQkTIEcaALcCACEABQm1F2ARABcBACIABAm4EKJAALIAAAAA.Nayuta:BAAALgADCgYJBQAAAA==.Nazal:BAAALgADCgEJAQAAAA==.',
Nc='Nc:BAAALgADCgIJAgABLgAECgEJAQAFAAAAAA==.Nctee:BAAALgAECgYJDQAAAA==.',
Ne='Necropally:BAAALgAECgEJAQAAAA==.Necrotizor:BAABLgAECn8bAAMRAAgJaRqjNgCKAQARAAgJaRqjNgCKAQAiAAEJNBVIJQA/AAAAAA==.Neonsalmandr:BAAALgAECgEJAQAAAA==.Nerrol:BAAALgADCgkJCQAAAA==.',
Ni='Nialliv:BAAALgADCgcJCQAAAA==.Nidvin:BAABLgAECn8WAAIZAAYJSBevMgBDAQAZAAYJSBevMgBDAQAAAA==.Nightsmoke:BAAALgAECgQJBQAAAA==.',
Nk='Nkb:BAAALgAECgYJDAAAAA==.',
Nn='Nnoitra:BAAALgADCgcJBwAAAA==.',
No='Noceman:BAAALgADCgEJAQAAAA==.Nock:BAAALgAECgcJCQAAAA==.Nogg:BAAALgADCgEJAQAAAA==.Nolanel:BAAALgAECgEJAQAAAA==.Noll:BAAALgADCgUJBQAAAA==.Nonattarius:BAAALgAECgYJCwAAAA==.Norezfou:BAABLgAECn8rAAMoAAkJiRpaCwCaAgAoAAkJiRpaCwCaAgACAAQJwhgyJQAaAQAAAA==.Nornir:BAAALgAECgIJAgAAAA==.Norran:BAAALgAECggJEgAAAA==.Norvera:BAAALgAECgIJAgAAAA==.Notalice:BAAALgAECgYJBwAAAA==.Notmywife:BAAALgAECgYJDQAAAA==.Novakri:BAAALgADCgMJAwAAAA==.',
Nu='Nuker:BAAALgAECgcJDwAAAA==.Nurobi:BAABLgAECn8dAAIeAAgJKRTnFACZAQAeAAgJKRTnFACZAQAAAA==.Nuundix:BAAALgAECgcJDwAAAA==.',
Ny='Nysel:BAAALgAECgkJAQAAAA==.Nysera:BAAALgADCggJCAAAAA==.Nyxy:BAAALgAECgUJDAAAAA==.',
Oc='Ocey:BAAALgADCgYJCwABLgAECgcJDwAFAAAAAA==.',
Od='Odyn:BAABLgAECn8YAAIWAAcJ0RUpNgClAQAWAAcJ0RUpNgClAQAAAA==.',
Oo='Ooyu:BAAALgAECgUJCwAAAA==.',
Or='Orangepeel:BAAALgADCgUJBQAAAA==.Oridk:BAAALgAECgcJDwABLgAFFAQJCgASALQWAA==.Orimage:BAAALgADCgkJDAABLgAFFAQJCgASALQWAA==.Oripal:BAAALgAECgUJBQABLgAFFAQJCgASALQWAA==.Orisham:BAAALgADCgkJCQABLgAFFAQJCgASALQWAA==.Oríon:BAACLgAFFH8KAAISAAQJtBYqCgA6AQASAAQJtBYqCgA6AQAuAAQKfyAAAxIACAnnI54FALACABIACAnnI54FALACAAMABQlqFgFTAAABAAAA.',
Ou='Outofmyele:BAAALgADCgQJBAAAAA==.',
Ow='Owoker:BAABLgAECn8WAAIOAAgJJRrDAgARAgAOAAgJJRrDAgARAgAAAA==.',
Pa='Pablo:BAABLgAECn8VAAIgAAcJ3xl6CwAHAgAgAAcJ3xl6CwAHAgAAAA==.Pancaked:BAAALgAECgEJAQABLgAFFAUJFQABAN0fAA==.Pancakedup:BAAALgAECgcJDAABLgAFFAUJFQABAN0fAA==.Pandozer:BAAALgAECggJEgAAAA==.Pankratos:BAABLgAECn8VAAMnAAgJkSOzFABoAgAnAAgJkSOzFABoAgAEAAMJLyCkIQAZAQAAAA==.Papaspud:BAABLgAECn8qAAIoAAgJmhFlFQCqAQAoAAgJmhFlFQCqAQAAAA==.Paradias:BAACLgAFFH8QAAITAAUJgheECABmAQATAAUJgheECABmAQAuAAQKfyUAAxMACAloIPIMAMoCABMACAlMIPIMAMoCACUABgmxFzEMAGIBAAAA.Pastor:BAAALgAECgUJBQAAAA==.Patpat:BAAALgADCgcJBgAAAA==.Paxxfist:BAABLgAECn8aAAILAAgJQQ+aIABBAQALAAgJQQ+aIABBAQAAAA==.',
Pe='Peachdevil:BAAALgADCgQJBAAAAA==.Penryn:BAAALgAECgEJAQAAAA==.Pentive:BAACLgAFFH8HAAIgAAMJjh2/AwAnAQAgAAMJjh2/AwAnAQAuAAQKfxUAAiAACAmnGzkFAL0CACAACAmnGzkFAL0CAAAA.Peppersgotem:BAAALgAECgEJAQAAAA==.Peppersham:BAABLgAECn8VAAMbAAYJIho1GwB1AQAbAAYJIho1GwB1AQAZAAIJVxkPgQCPAAAAAA==.Pepromene:BAAALgADCgUJBQAAAA==.Perff:BAAALgADCgYJBQAAAA==.Perhaps:BAABLgAECn8cAAInAAgJGyKKBwANAwAnAAgJGyKKBwANAwAAAA==.Petesdragin:BAABLgAECn8XAAIIAAYJEhd0CwCWAQAIAAYJEhd0CwCWAQAAAA==.',
Pf='Pfftpfft:BAAALgAECgYJCgAAAA==.',
Ph='Phatdanny:BAABLgAECn8VAAIWAAgJaxgRIwD5AQAWAAgJaxgRIwD5AQAAAA==.Phatdumpy:BAABLgAECn8jAAQSAAgJdBIKDgDGAQASAAgJpQ4KDgDGAQAQAAcJcROvOgDEAQADAAQJ7wr2XADOAAAAAA==.Phattphatt:BAABLgAECn8bAAIgAAcJBxorBwDHAQAgAAcJBxorBwDHAQAAAA==.Phonycheese:BAAALgAECggJDwAAAA==.Phur:BAABLgAFFH8GAAIdAAIJjBA3EgCWAAAdAAIJjBA3EgCWAAAAAA==.',
Pi='Pinbal:BAAALgAECgQJBAAAAA==.Pixen:BAABLgAECn8eAAIRAAgJdBLZKgC5AQARAAgJdBLZKgC5AQAAAA==.',
Pl='Plagueiss:BAABLgAECn8cAAIVAAgJjhrKPABEAgAVAAgJjhrKPABEAgAAAA==.',
Po='Pocalypse:BAAALgAECgYJBQAAAA==.Pocketsand:BAAALgADCgYJBgAAAA==.Ponkeylips:BAAALgAECgUJDgAAAA==.Portstar:BAABLgAECn8cAAMUAAkJbAujOQC8AQAUAAkJTwmjOQC8AQAXAAYJzQ2gDgDZAAAAAA==.Powwerbottom:BAAALgADCgEJAQAAAA==.',
Pr='Precast:BAAALgADCgUJCgAAAA==.Prestoresto:BAAALgAECgEJAQAAAA==.Prieske:BAABLgAECn8YAAQPAAYJfR27FQCPAQAPAAYJchy7FQCPAQACAAQJtBeXIgAsAQAoAAUJ+RmQSAAXAQAAAA==.Primed:BAABLgAECn8zAAIgAAkJ0RBRBQACAgAgAAkJ0RBRBQACAgAAAA==.Privxd:BAABLgAFFH8IAAIMAAQJwBj4CQA5AQAMAAQJwBj4CQA5AQAAAA==.Prunesa:BAAALgADCgcJBQAAAA==.',
Pu='Pungla:BAAALgAECgMJAwAAAA==.',
['Pî']='Pîper:BAAALgADCgYJBgAAAA==.',
['Pï']='Pït:BAAALgAECggJEAAAAA==.',
Qp='Qprawindfury:BAAALgAECgUJDAAAAA==.',
Qu='Quadtwat:BAAALgAECgQJBwAAAA==.Quahogger:BAAALgAECgYJCwAAAA==.Quazer:BAAALgAECgEJAgAAAA==.',
Ra='Radical:BAAALgAECgcJCQAAAA==.Railyard:BAAALgADCgMJAwABLgAECgIJAgAFAAAAAA==.Raivn:BAAALgADCgEJAQAAAA==.Rajasta:BAAALgAECgQJBwAAAA==.Rajzova:BAAALgADCgcJCgABLgAECgYJDQAFAAAAAA==.Randomclown:BAAALgAECgMJAwAAAA==.Rapi:BAAALgAECgMJAwAAAA==.Rascalfats:BAAALgAECgQJBwAAAA==.Rashii:BAAALgAECgcJDgAAAA==.Rawor:BAABLgAECn8dAAIRAAcJVxEKPAB4AQARAAcJVxEKPAB4AQAAAA==.',
Re='Rebaderchi:BAACLgAFFH8HAAIKAAMJoAsnHwDeAAAKAAMJoAsnHwDeAAAuAAQKfx8AAgoACAkrHqEZALoCAAoACAkrHqEZALoCAAAA.Relyne:BAAALgADCgYJBgAAAA==.Remo:BAAALgAECgMJAwAAAA==.Remoria:BAAALgAECgcJBwAAAA==.Renildan:BAAALgAECgYJDwAAAA==.Renscope:BAAALgADCgUJBQAAAA==.Resala:BAAALgADCgYJBgAAAA==.Rev:BAAALgADCgMJAwAAAA==.Revanhawk:BAAALgADCgkJEQAAAA==.Revna:BAAALgADCgcJBwAAAA==.Rezputan:BAABLgAECn8UAAIVAAgJiBiLIwD2AQAVAAgJiBiLIwD2AQAAAA==.',
Rh='Rholand:BAABLgAECn8UAAMHAAgJRh1TCABlAgAHAAgJEB1TCABlAgAfAAIJAxb8OACCAAAAAA==.',
Ri='Rind:BAAALgAECgYJCQAAAA==.Rioken:BAABLgAECn8eAAMRAAkJWRcWFgAxAgARAAkJWRcWFgAxAgAiAAEJgxB2bgA4AAAAAA==.Riolobo:BAAALgADCgIJAgAAAA==.Riorage:BAAALgAECgcJEgAAAA==.Ritz:BAAALgAECgEJAQAAAA==.Rizzoy:BAABLgAECn8nAAIHAAcJth1nDgAIAgAHAAcJth1nDgAIAgAAAA==.',
Ro='Rohoth:BAAALgAECgIJAgAAAA==.Rolaiya:BAAALgADCgYJBgAAAA==.Rollo:BAAALgADCgYJEgAAAA==.Rolor:BAAALgADCgYJBgAAAA==.Rookiefister:BAAALgAECgQJAwAAAA==.Ross:BAECLgAFFH8IAAILAAQJLiPXCACUAQALAAQJLiPXCACUAQAuAAQKfxsAAgsABgmnJaAMACACAAsABgmnJaAMACACAAAA.Rovyr:BAABLgAECn8oAAMIAAgJ/h94AgDSAgAIAAgJ/h94AgDSAgAOAAEJuAHgRQAeAAAAAA==.',
Ru='Ruckabis:BAABLgAECn8hAAMZAAkJfB8PCwB9AgAZAAkJfB8PCwB9AgAbAAEJSwdbaAAuAAAAAA==.Rundeezyy:BAAALgADCgYJCQAAAA==.',
Ry='Rylos:BAABLgAECn8YAAIVAAgJ8go2QAB8AQAVAAgJ8go2QAB8AQAAAA==.Rytotem:BAAALgAECgMJCAAAAA==.Ryumi:BAAALgADCgkJCwAAAA==.Ryvington:BAAALgADCgYJCAAAAA==.',
Sa='Saansula:BAAALgAECgUJDAAAAA==.Sabian:BAABLgAECn8ZAAIeAAkJlxAFDgDtAQAeAAkJlxAFDgDtAQAAAA==.Saintjeb:BAABLgAFFH8FAAIYAAIJ5Aw6CAB6AAAYAAIJ5Aw6CAB6AAAAAA==.Saitami:BAAALgAECgEJAQAAAA==.Saitamå:BAAALgAECgYJDAAAAA==.Sakisan:BAAALgAECgEJAQAAAA==.Salinity:BAABLgAECn8eAAMiAAgJfiNuBwBRAgAiAAcJRSBuBwBRAgARAAgJSSEbHAAHAgAAAA==.Samanaras:BAAALgAECgYJDgAAAA==.Sanari:BAAALgADCgMJAwAAAA==.Santiago:BAAALgAECgQJDQAAAA==.Saratoga:BAAALgAECgcJDQAAAA==.Sarkana:BAABLgAECn8eAAIjAAkJIRsXCgBvAgAjAAkJIRsXCgBvAgAAAA==.Sarticor:BAAALgAECgEJAQAAAA==.Sassquatch:BAABLgAECn8VAAMVAAcJLA27cgD8AAAVAAcJ0wy7cgD8AAAGAAEJIAXLOwAlAAAAAA==.Saxonn:BAABLgAECn8hAAMbAAgJ+QtpIQBFAQAbAAgJ+QtpIQBFAQAZAAMJaQMziABzAAAAAA==.Saydis:BAAALgAECgMJBgAAAA==.',
Sc='Schuftt:BAABLgAECn8UAAMXAAgJEho0AgDYAQAXAAgJEho0AgDYAQAcAAEJ9BQODgBGAAAAAA==.',
Se='Seafoodtower:BAAALgAECgEJAQAAAA==.Sebattan:BAAALgAECgEJAgAAAA==.Seleine:BAAALgADCgEJAQABLgAECgkJLQAUAHsXAA==.Sello:BAAALgAECgEJAgAAAA==.Seltzers:BAAALgADCgQJCgAAAA==.Selunella:BAAALgADCgEJAQABLgAECgUJDQAFAAAAAA==.Selvester:BAABLgAECn8dAAInAAcJUyO8BgBqAgAnAAcJUyO8BgBqAgAAAA==.Senadria:BAABLgAECn8UAAIKAAUJkwlthQCJAAAKAAUJkwlthQCJAAAAAA==.Senseishifu:BAABLgAECn8ZAAInAAgJuA7NPgBKAQAnAAgJuA7NPgBKAQAAAA==.Seorsen:BAAALgADCgcJEAAAAA==.Servinghunt:BAAALgAECgYJCwAAAA==.Sevalandre:BAAALgADCgYJBgABLgAECggJGwAVAJwXAA==.',
Sh='Shamatrest:BAAALgAECgEJAwABLgAECgkJKAAVANgkAA==.Shamina:BAACLgAFFH8HAAIBAAMJnATFBQDXAAABAAMJnATFBQDXAAAuAAQKfxUAAgEABwmvDiIQALUBAAEABwmvDiIQALUBAAAA.Shamite:BAAALgAECgMJAwABLgAECgcJCQAFAAAAAA==.Shammalin:BAABLgAECn8fAAMbAAcJlwoJKQAYAQAbAAcJlwoJKQAYAQAZAAUJlgwyRwDkAAAAAA==.Shamminator:BAAALgADCgMJAwAAAA==.Shamorex:BAABLgAECn8kAAIbAAcJuhYKHQBlAQAbAAcJuhYKHQBlAQAAAA==.Shanoth:BAAALgAECgYJBgABLgAECggJGwAVAJwXAA==.Sharkbones:BAAALgAECgEJAQAAAA==.Shatter:BAAALgAECgcJCgAAAA==.Shax:BAAALgAECgUJBgABLgAECggJHgAiAH4jAA==.Shiftyy:BAAALgAECgYJBwAAAA==.Shogun:BAAALgADCgQJCAAAAA==.Shteph:BAAALgADCgkJEwAAAA==.Shîftfaced:BAAALgAECgIJAgAAAA==.',
Si='Siaerosia:BAAALgADCgEJAQAAAA==.',
Sk='Skaarr:BAABLgAECn8VAAIHAAgJ3wjYJwA5AQAHAAgJ3wjYJwA5AQAAAA==.',
Sl='Slayn:BAAALgAECgYJEQAAAA==.Slowhealsboi:BAAALgAECgQJBAAAAA==.Slushpuppie:BAAALgADCgYJBgAAAA==.Slyrak:BAABLgAECn8gAAMOAAgJ7BcBAwD+AQAOAAgJ7BcBAwD+AQAIAAMJoQhdIQBhAAAAAA==.',
Sm='Smithbruh:BAEALgAECgQJBAABLgAECggJIAAnAMghAA==.Smitus:BAAALgAECgQJBwAAAA==.Smokescale:BAAALgADCgcJCAAAAA==.',
Sn='Snackie:BAABLgAECn8VAAIZAAgJhhhbEAA7AgAZAAgJhhhbEAA7AgAAAA==.Sneakyjewel:BAAALgADCgcJBwAAAA==.Snotpig:BAAALgAECggJBwAAAA==.',
So='Solarious:BAAALgAECgEJAQAAAA==.Sorscrasus:BAAALgADCgUJCAAAAA==.Soulcolektor:BAAALgADCgcJDwAAAA==.Souled:BAAALgADCgYJBgAAAA==.',
Sp='Sparroh:BAAALgADCgEJAQAAAA==.Spikedriver:BAABLgAECn8eAAIQAAkJuw84KACxAQAQAAkJuw84KACxAQAAAA==.Spradwurd:BAAALgAECgUJCAAAAA==.',
Sq='Squee:BAABLgAECn8UAAMEAAgJuBVHFwBtAQAEAAgJuBVHFwBtAQAnAAEJ1wF3mQAaAAABLgAECggJFAAEALgVAA==.',
St='Stantonio:BAAALgAECgcJDgAAAA==.Stariane:BAABLgAECn8dAAIJAAgJbR6gBQBaAgAJAAgJbR6gBQBaAgAAAA==.Startaster:BAAALgAFFAEJAQAAAA==.Starvoid:BAAALgAECgEJAQAAAA==.Steaktartare:BAAALgAECgcJEgAAAA==.Steelfist:BAAALgAECgYJCgAAAA==.Steelpunch:BAAALgAECgUJCAAAAA==.Steelwill:BAAALgAECgIJAgAAAA==.Stonii:BAAALgADCgUJBQAAAA==.Stony:BAABLgAECn8gAAIQAAcJ1CCLEQBFAgAQAAcJ1CCLEQBFAgAAAA==.Stonyy:BAAALgAECgQJBQAAAA==.Strelizia:BAAALgAECgIJAgAAAA==.Stressful:BAAALgADCgQJBAAAAA==.',
Su='Suetekh:BAAALgADCgUJBQAAAA==.Sukidaiyo:BAAALgAECgcJDQAAAA==.Summers:BAAALgAECgMJCAAAAA==.Sumonmyface:BAAALgAECgQJBgABLgAECggJIwASAHQSAA==.Sunshield:BAAALgADCgkJCwAAAA==.Superillbomb:BAAALgADCgcJCwAAAA==.Suraug:BAAALgADCgcJBwAAAA==.Suzakku:BAAALgAECgEJAQAAAA==.',
Sw='Swampraught:BAABLgAECn8dAAMRAAcJNxZRMACiAQARAAcJNxZRMACiAQAiAAEJtA2ecAA1AAAAAA==.',
Sy='Syd:BAAALgADCgYJBgAAAA==.Syletage:BAAALgAECgMJBAAAAA==.Synd:BAAALgADCgEJAQAAAA==.Synrae:BAAALgAECgcJBgAAAA==.Syral:BAAALgAECgMJBwAAAA==.Syrion:BAAALgAECgQJBAAAAA==.Sythrane:BAAALgADCgcJBwAAAA==.',
Ta='Taarii:BAAALgADCggJCAAAAA==.Talisoudwave:BAAALgAECgUJDAABLgAECggJGgAMABElAA==.Talomeo:BAAALgAECgIJAgAAAA==.Taradan:BAAALgAECgEJAQAAAA==.Taraxus:BAAALgADCgUJBQAAAA==.Tateraider:BAABLgAECn8qAAIfAAgJlB7gBABfAgAfAAgJlB7gBABfAgAAAA==.Taurnator:BAAALgAECgIJAwAAAA==.Taylorswift:BAAALgAECgMJBgAAAA==.Tayven:BAAALgADCgEJAQAAAA==.',
Te='Telain:BAABLgAECn8oAAQjAAgJLBU2FADwAQAjAAgJLBU2FADwAQAWAAQJCAy/4QDKAAAYAAIJhxZDIgCEAAAAAA==.Tensuki:BAAALgAECgEJAQAAAA==.Teslah:BAAALgADCgQJBAAAAA==.',
Th='Thakilla:BAABLgAECn8oAAIeAAgJmhNbEQDAAQAeAAgJmhNbEQDAAQAAAA==.Thanosonmage:BAAALgADCgcJBwAAAA==.Thavik:BAAALgADCgEJAwAAAA==.Theolodin:BAAALgAECgQJBwAAAA==.Thordrik:BAAALgAECgQJBQAAAA==.Thorix:BAAALgAECgcJEwAAAA==.Thotmir:BAAALgAECgMJAwAAAA==.Thícc:BAAALgADCgkJCgAAAA==.',
Ti='Tigerburn:BAAALgADCgkJCQAAAA==.Tikibiki:BAAALgADCgMJAwAAAA==.Timbereses:BAAALgADCgUJBQAAAA==.Timberreaper:BAAALgAECgIJAgAAAA==.Tinyz:BAABLgAECn8UAAMoAAYJ3BN2HQBdAQAoAAYJ3BN2HQBdAQACAAUJTwZ4NgCwAAAAAA==.',
To='Tolua:BAAALgAECgUJCAAAAA==.Tonata:BAABLgAECn8UAAMIAAkJ3AcuIwBfAQAIAAgJgQUuIwBfAQANAAkJ6Ao7KgADAQAAAA==.Tonythetiger:BAAALgAECgEJAQABLgAECggJHwAGAKIcAA==.Tootsie:BAAALgADCgYJEAAAAA==.',
Tr='Trenton:BAAALgADCgUJBwAAAA==.Trexlot:BAAALgAECgIJAwAAAA==.Trinjal:BAABLgAECn8dAAILAAgJlRpCDQAWAgALAAgJlRpCDQAWAgAAAA==.Trishift:BAAALgAECgQJBQAAAA==.Trueshru:BAAALgAECgIJAwAAAA==.',
Tu='Tubular:BAAALgAECgMJBQAAAA==.Tuskadin:BAACLgAFFH8FAAIWAAMJJRqlLgD5AAAWAAMJJRqlLgD5AAAuAAQKfyYAAhYACAmtIqkbAMQCABYACAmtIqkbAMQCAAAA.',
Tw='Tweeq:BAAALgADCgkJCQAAAA==.',
Ty='Tyjan:BAAALgAECgYJDgAAAA==.Tyrana:BAAALgAECgMJAwAAAA==.Tyriq:BAAALgADCgYJBgAAAA==.',
Un='Unclothed:BAABLgAECn8UAAIgAAYJJAiSEwDmAAAgAAYJJAiSEwDmAAAAAA==.Unicorn:BAAALgADCggJCAAAAA==.Untòld:BAAALgADCggJCAABLgAECgcJFQAUAHUNAA==.',
Va='Valentine:BAAALgADCgIJAgAAAA==.Valitymage:BAAALgADCgEJAQAAAA==.Varyusha:BAAALgAECgMJBAAAAA==.',
Ve='Velene:BAAALgADCgEJAQABLgAECgkJLQAUAHsXAA==.Venzallow:BAAALgAECgUJBwAAAA==.Veralynn:BAAALgADCgcJBwAAAA==.Veravibes:BAAALgAECgQJCwAAAA==.Vermagnus:BAABLgAECn8UAAInAAcJbho2KwCyAQAnAAcJbho2KwCyAQAAAA==.Vespor:BAABLgAECn8ZAAIMAAYJHR9FFgATAgAMAAYJHR9FFgATAgAAAA==.',
Vi='Viktorya:BAABLgAECn8eAAIIAAcJGheZFgDlAQAIAAcJGheZFgDlAQAAAA==.Vilelyn:BAAALgAECgYJDwABLgAECgcJFgAWAEoZAA==.Viloria:BAABLgAECn8dAAIaAAcJcxEdDQA7AQAaAAcJcxEdDQA7AQAAAA==.Vincent:BAAALgADCgkJEwAAAA==.Virrard:BAABLgAECn8iAAMQAAgJxRxxFgAbAgAQAAgJxRxxFgAbAgADAAIJYA+adQBoAAAAAA==.Vitalyellow:BAAALgADCgYJBgAAAA==.',
Vl='Vladimor:BAAALgAECgYJEgAAAA==.Vladimyrr:BAAALgAECgcJEQAAAA==.',
Vo='Vodan:BAAALgADCgEJAQAAAA==.Voidplague:BAAALgAECgYJDQAAAA==.Voidscarred:BAAALgAECgQJEQAAAA==.Vozrezz:BAABLgAECn8YAAMEAAcJWh1xDwDEAQAEAAcJSxpxDwDEAQAnAAYJ/RcVGgBkAQAAAA==.',
Vu='Vualake:BAAALgADCgYJCgAAAA==.',
Vy='Vyridian:BAAALgAECgQJAwABLgAECgYJEwAFAAAAAA==.',
['Vë']='Vëda:BAABLgAECn8gAAIoAAkJng6hEwC+AQAoAAkJng6hEwC+AQAAAA==.',
Wa='Wardragon:BAAALgADCgcJCwAAAA==.Warrwras:BAAALgADCgcJBwAAAA==.Wasical:BAAALgAECgQJAwAAAA==.',
Wh='Wheaties:BAAALgAECgUJBQABLgAECggJHwAGAKIcAA==.',
Wi='Wicker:BAABLgAECn8mAAIaAAgJriLBAgB+AgAaAAgJriLBAgB+AgAAAA==.Wickievoker:BAAALgADCgkJCQABLgAECggJJgAaAK4iAA==.Wintin:BAAALgAECgEJAgAAAA==.Wiskey:BAAALgAECgEJAQAAAA==.',
Wo='Wolford:BAABLgAECn8WAAIMAAYJNx21HQDWAQAMAAYJNx21HQDWAQAAAA==.Woogie:BAAALgADCgYJCgAAAA==.Wordz:BAAALgAECgEJAgAAAA==.',
Wr='Wras:BAABLgAECn8VAAIGAAYJiByfDgCHAQAGAAYJiByfDgCHAQAAAA==.Wretched:BAAALgAECgcJBQAAAA==.',
Wy='Wyrnn:BAAALgADCgYJDAAAAA==.Wysstical:BAAALgAECgcJBwABLgAFFAUJFQABAN0fAA==.',
['Wò']='Wòbbles:BAAALgAECgQJCgAAAA==.',
Xa='Xalnova:BAAALgADCgYJBgAAAA==.Xandos:BAAALgADCgEJAQAAAA==.Xandrah:BAAALgAECgYJDwAAAA==.Xanslash:BAABLgAECn8aAAIKAAgJER8OHADhAQAKAAgJER8OHADhAQAAAA==.Xari:BAACLgAFFH8VAAIUAAUJJBcSIwBiAQAUAAUJJBcSIwBiAQAuAAQKfyUAAhQACQluIgcSADsDABQACQluIgcSADsDAAAA.',
Xh='Xhalo:BAAALgADCggJCAAAAA==.',
Xi='Xiansai:BAABLgAECn8fAAICAAkJbxaSCgAbAgACAAkJbxaSCgAbAgAAAA==.',
Ya='Yappey:BAABLgAECn8XAAInAAYJICPgDwDMAQAnAAYJICPgDwDMAQAAAA==.',
Ye='Yehni:BAABLgAECn81AAIoAAkJFSTJAACDAwAoAAkJFSTJAACDAwAAAA==.',
Ys='Ys:BAAALgADCgEJAQABLgAECgkJIAAoAJ4OAA==.',
Za='Zaesha:BAAALgADCgYJCAAAAA==.Zalarii:BAAALgADCgEJAgAAAA==.Zarox:BAABLgAECn8ZAAIVAAkJ6hByLQDEAQAVAAkJ6hByLQDEAQAAAA==.',
Ze='Zeroelement:BAABLgAECn8WAAIjAAgJPB9DHQCdAQAjAAgJPB9DHQCdAQAAAA==.',
Zi='Zimgir:BAAALgADCgEJAQAAAA==.',
Zo='Zombiehippo:BAABLgAECn8oAAIUAAkJsBmuFQBtAgAUAAkJsBmuFQBtAgAAAA==.Zorcons:BAAALgAECgEJAQAAAA==.',
Zu='Zuuzuu:BAAALgADCgEJAQAAAA==.',
['Áu']='Áutarch:BAAALgAECgYJEgAAAA==.',
['Èl']='Èlty:BAAALgAECgMJAwAAAA==.',
['Ðe']='Ðemøn:BAAALgAECgMJBAAAAA==.',
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
