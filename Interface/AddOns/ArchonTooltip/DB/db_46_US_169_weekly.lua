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

local lookup = {'DemonHunter-Havoc','Mage-Frost','Paladin-Holy','Paladin-Retribution','Priest-Holy','Unknown-Unknown','Warrior-Fury','DemonHunter-Devourer','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Vengeance','Druid-Balance','Warlock-Destruction','Warlock-Demonology','DeathKnight-Unholy','Hunter-BeastMastery','Priest-Shadow','Warlock-Affliction','Warrior-Protection','Warrior-Arms','Paladin-Protection','Druid-Restoration','Druid-Feral','Monk-Windwalker','Monk-Brewmaster','Shaman-Elemental','Shaman-Restoration','Rogue-Subtlety','DeathKnight-Frost','DeathKnight-Blood','Mage-Arcane','Shaman-Enhancement','Priest-Discipline','Monk-Mistweaver','Mage-Fire','Druid-Guardian','Hunter-Survival','Hunter-Marksmanship',}
local provider = {region='US',realm='Nordrassil',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aairidari:BAABLgAECn8UAAIBAAYJOgvlFQD1AAABAAYJOgvlFQD1AAAAAA==.',
Ab='Abruna:BAAALgAECgYJDgABLgAFFAUJEAACACUaAA==.Abruno:BAACLgAFFH8QAAICAAUJJRoGGwBeAQACAAUJJRoGGwBeAQAuAAQKfyYAAgIACQn9IAgQAEgDAAIACQn9IAgQAEgDAAAA.Abruto:BAAALgADCgYJBgABLgAFFAUJEAACACUaAA==.',
Ad='Adrians:BAABLgAECn8fAAICAAcJsBRcOQCDAQACAAcJsBRcOQCDAQAAAA==.',
Ae='Aeown:BAABLgAECn8UAAMDAAYJlgljJwAPAQADAAYJlgljJwAPAQAEAAEJbAK84QAmAAABLgAECggJJQAFAJMUAA==.Aerdis:BAAALgAECgEJAQABLgAECgYJCwAGAAAAAA==.',
Ag='Aggerwator:BAAALgAECgEJAQABLgAECgcJFQAHAMkhAA==.',
Ah='Ahsóká:BAAALgAECgQJBQAAAA==.',
Ak='Akames:BAAALgAECgQJBwABLgAFFAQJCAAIAA4OAA==.',
Al='Alahrî:BAABLgAECn8mAAQJAAkJSxPiFgDhAQAJAAgJLBHiFgDhAQAKAAYJCQtlBQBZAQALAAQJmwu+MACeAAAAAA==.Alandrìas:BAABLgAECn8bAAIMAAcJjQ3wCAAaAQAMAAcJjQ3wCAAaAQAAAA==.Aloiss:BAAALgADCgMJAwAAAA==.Alphael:BAAALgADCgYJBgAAAA==.Alror:BAABLgAECn8oAAINAAkJsB3YBQA9AwANAAkJsB3YBQA9AwAAAA==.Altera:BAABLgAECn8eAAIJAAcJphbxBgDPAQAJAAcJphbxBgDPAQAAAA==.',
Am='Amelya:BAAALgAECgcJDwAAAA==.Amuri:BAAALgAECgUJBwAAAA==.',
An='Andere:BAAALgAECgYJBgAAAA==.Androonatorz:BAACLgAFFH8RAAIDAAUJLBgaBQCgAQADAAUJLBgaBQCgAQAuAAQKfyMAAwMACQnTHlYHAPcCAAMACQnTHlYHAPcCAAQABAn+ETS+AAoBAAAA.Angelø:BAAALgAECgEJAQAAAA==.Antagony:BAAALgAECgEJAQAAAA==.Antheavari:BAAALgADCgYJBgAAAA==.',
Ar='Ardell:BAEALgAECgYJBgAAAA==.Ardemus:BAABLgAECn8XAAMOAAYJGhJUCgD/AAAOAAYJGhJUCgD/AAAPAAEJYAADNAEWAAAAAA==.Arkena:BAAALgAECgIJAgAAAA==.Arkenai:BAAALgADCgcJDQAAAA==.Arveiturace:BAAALgAECgEJAQAAAA==.',
As='Ashborrn:BAAALgAECgUJBwAAAA==.Ashtar:BAAALgAECgYJEQAAAA==.Ashtomouth:BAAALgAECgYJEQAAAA==.Astorath:BAAALgADCgEJAgAAAA==.Asukajo:BAAALgAECgMJAwAAAA==.',
Aw='Awaken:BAAALgAECgcJDwAAAA==.Awoomonk:BAAALgAECgIJAgAAAA==.',
Az='Azorei:BAAALgADCgIJAgAAAA==.',
Ba='Baconegg:BAACLgAFFH8PAAIQAAQJIRYRGABFAQAQAAQJIRYRGABFAQAuAAQKfyEAAhAACAlFIV8VAPsCABAACAlFIV8VAPsCAAAA.Balddrex:BAAALgADCgkJCQAAAA==.Balefire:BAABLgAECn8bAAMPAAgJFxhZGwDQAQAPAAgJFxhZGwDQAQAOAAIJ7xhkHABMAAAAAA==.Bamboom:BAAALgADCgQJBAAAAA==.Barma:BAAALgADCgcJBwAAAA==.Barraki:BAAALgADCgIJAgABLgAECggJHAARAPAMAA==.Basili:BAAALgADCgUJBwAAAA==.',
Bd='Bd:BAAALgAECgEJAgAAAA==.',
Be='Beeper:BAAALgAECgYJBgAAAA==.Beldanner:BAAALgADCgkJDAAAAA==.Beltirra:BAAALgAECgMJBAAAAA==.Benan:BAAALgADCgUJBQAAAA==.Bengalnug:BAAALgADCgQJBAAAAA==.',
Bi='Bigwill:BAABLgAECn8eAAICAAgJzBsrHQD8AQACAAgJzBsrHQD8AQAAAA==.',
Bl='Blackfeet:BAAALgAECgYJBwAAAA==.Blango:BAAALgAECgMJAwAAAA==.Blargy:BAABLgAECn8mAAINAAgJPxm4CwDTAQANAAgJPxm4CwDTAQAAAA==.Blex:BAAALgADCggJCAAAAA==.Bloodshed:BAAALgADCgkJDwAAAA==.Bluewaffles:BAAALgAECgEJAQAAAA==.',
Bo='Boudicah:BAAALgADCgEJAQAAAA==.',
Br='Braicel:BAACLgAFFH8SAAISAAUJDiKaAgCTAQASAAUJDiKaAgCTAQAuAAQKfyYAAhIACQm+I4UEAE0DABIACQm+I4UEAE0DAAAA.Breedableram:BAAALgADCgYJBgABLgAECggJGgATADsaAA==.Brimara:BAAALgAFFAEJAQAAAA==.Brythorn:BAAALgADCgEJAQAAAA==.',
Bu='Bubbleosevên:BAAALgADCgkJCQAAAA==.Bucketojoy:BAAALgAECgIJAgABLgAECggJGwABABQOAA==.',
['Bì']='Bìgred:BAAALgADCgEJAQAAAA==.',
Ca='Cacadookie:BAAALgAECgEJAQAAAA==.Calegorm:BAAALgADCgYJCwAAAA==.Caliburne:BAABLgAECn8ZAAQUAAgJdx9bBQAJAgAUAAcJQR1bBQAJAgAVAAgJ6R1wCQBtAQAHAAYJGw+YUQBiAQAAAA==.Caliypso:BAAALgAECgYJCQAAAA==.Cambro:BAABLgAECn8WAAMEAAYJehnMTAAlAQAEAAYJTRnMTAAlAQAWAAEJpgRASQAgAAAAAA==.Candie:BAAALgAECgEJAQAAAA==.Candierain:BAAALgAECgEJAQAAAA==.Canoe:BAABLgAECn8qAAQNAAgJYBd2KwCmAQANAAcJAhV2KwCmAQAXAAcJkhfsIQByAQAYAAIJ+gAKOwAYAAAAAA==.Capz:BAACLgAFFH8bAAMVAAcJWh8pAABHAgAVAAcJsh4pAABHAgAHAAQJ8yBRBwB3AQAuAAQKfyEAAxUACQnPIz0DANsCABUACAkWJT0DANsCAAcACQlnFp4PANYCAAAA.Carcaradon:BAAALgAECgEJAwAAAA==.Carta:BAAALgAECgMJBAAAAA==.Caulfield:BAAALgAECgEJAQAAAA==.',
Cc='Ccstarscream:BAAALgAECgEJAQAAAA==.',
Ce='Ceez:BAAALgAECgUJDAAAAA==.Celebrïmbor:BAAALgAECgMJAQAAAA==.',
Ch='Chair:BAAALgAECggJDQABLgAECggJHgACAHAWAA==.Chiyori:BAAALgADCgIJAQAAAA==.Chongy:BAAALgAECgIJAwABLgAECgUJCgAGAAAAAA==.Chopperr:BAAALgADCgMJBQAAAA==.Chèn:BAAALgAECgYJCwAAAA==.',
Ci='Cindrella:BAABLgAECn8eAAICAAgJcBbNcADyAQACAAgJcBbNcADyAQAAAA==.Circa:BAAALgADCgIJAgAAAA==.',
Cl='Clani:BAAALgADCgIJAgAAAA==.Clayre:BAACLgAFFH8KAAIOAAMJTxZ+AgAPAQAOAAMJTxZ+AgAPAQAuAAQKfzQAAg4ACQmAIxwAAD0DAA4ACQmAIxwAAD0DAAAA.Clow:BAABLgAECn8VAAMHAAcJySHOGgB1AgAHAAYJhyPOGgB1AgAVAAIJ6RrzKgCcAAAAAA==.',
Co='Comparabull:BAAALgADCgcJEQAAAA==.Coolcrush:BAABLgAECn8dAAMZAAcJpiPYBQA1AgAZAAcJwh/YBQA1AgAaAAYJoCFXCgDlAQAAAA==.Corgnelius:BAAALgADCgYJDAAAAA==.Corven:BAACLgAFFH8OAAIPAAUJahnBDQBrAQAPAAUJahnBDQBrAQAuAAQKfzQAAw8ACQkiHVwKAGgCAA8ACQkiHVwKAGgCABMAAQkAALg0ADIAAAAA.Corvenicus:BAAALgAECgMJAwAAAA==.',
Cr='Crashbash:BAAALgADCgMJAwAAAA==.Crosis:BAAALgAECgYJDgAAAA==.Cryovox:BAAALgADCgIJAgAAAA==.',
Cu='Cumazzing:BAACLgAFFH8NAAIEAAUJ+CQjBgCNAQAEAAUJ+CQjBgCNAQAuAAQKfx0AAgQACQkwJbYCAK4DAAQACQkwJbYCAK4DAAAA.',
Da='Dadrin:BAAALgADCgYJBgAAAA==.Daedyxes:BAAALgAECgYJEAAAAA==.Daerodos:BAAALgAECgUJCgAAAA==.Daiskei:BAAALgAECgcJDAAAAA==.Dangerr:BAAALgADCgcJBwAAAA==.Darfretail:BAABLgAECn8WAAIHAAgJ+xCVEwCZAQAHAAgJ+xCVEwCZAQAAAA==.Darkdemon:BAAALgADCgcJDAAAAA==.Darkmagi:BAAALgAECgMJBAAAAA==.Dasherdeez:BAAALgADCggJDQAAAA==.Daygath:BAABLgAECn8ZAAIbAAcJrhHQFwBUAQAbAAcJrhHQFwBUAQAAAA==.',
De='Deadlyiris:BAABLgAECn8cAAMVAAgJJx2XAgBOAgAVAAgJJx2XAgBOAgAHAAYJHxCUSgB7AQABLgAECgYJFQAcAF8jAA==.Deatharin:BAAALgAECgQJBwAAAA==.Demonbulio:BAABLgAECn8XAAIBAAcJYxJEDAB4AQABAAcJYxJEDAB4AQAAAA==.Demonisthicc:BAAALgAECgIJAwABLgAECggJGgATADsaAA==.Demonskitten:BAABLgAECn8aAAITAAgJOxqZAQD1AQATAAgJOxqZAQD1AQAAAA==.Demonslayeer:BAAALgADCgMJBAAAAA==.Devlyne:BAAALgADCgMJAwAAAA==.',
Di='Ding:BAAALgAECgYJEAAAAA==.Direwolf:BAAALgAECgQJBQAAAA==.Dirtyearl:BAABLgAECn8hAAIEAAcJ4Bb2MgB3AQAEAAcJ4Bb2MgB3AQAAAA==.Dithehealer:BAABLgAECn8XAAMWAAgJ/R1lBgDAAQAWAAgJ/R1lBgDAAQAEAAEJlwdxTAEuAAAAAA==.Divain:BAAALgADCgEJAQAAAA==.',
Do='Doalina:BAAALgADCgQJBgAAAA==.Domidia:BAABLgAECn8gAAICAAYJOh77MQCcAQACAAYJOh77MQCcAQAAAA==.Donkeyshot:BAAALgAECgQJCgABLgAECgYJEgAGAAAAAA==.Doogie:BAAALgADCgEJAQAAAA==.',
Dr='Dracon:BAAALgADCgkJCQAAAA==.Draconfel:BAAALgAECgMJAwAAAA==.Draglone:BAAALgADCgMJAwABLgAECgYJBgAGAAAAAA==.Dranåk:BAAALgAECgQJBAAAAA==.Drbadtouch:BAAALgAECgEJAQAAAA==.Dreamfyres:BAACLgAFFH8RAAMKAAUJuSDmAQB9AQAKAAUJ2B/mAQB9AQALAAMJ3SHaEAAqAQAuAAQKfyQAAwoACQnqJAkBAF0DAAoACAmKJQkBAF0DAAsABgnOIk0PAJkBAAAA.Drenamai:BAAALgAECgYJEQAAAA==.Drewetta:BAAALgAECggJEwAAAA==.Drmombo:BAAALgAECgQJAwAAAA==.',
Du='Duhmptruhk:BAAALgAECgYJCwABLgAECgcJBwAGAAAAAA==.Durbana:BAAALgADCgUJBQAAAA==.Duskariel:BAAALgADCgMJBAAAAA==.',
Dy='Dyson:BAAALgAECgcJEgAAAA==.',
['Dé']='Démonicblood:BAAALgAECgUJBQAAAA==.',
Eh='Ehmehzing:BAACLgAFFH8HAAIEAAMJrCOKDgA2AQAEAAMJrCOKDgA2AQAuAAQKfygAAgQACQk9Ja4BAMgDAAQACQk9Ja4BAMgDAAEuAAUUBQkNAAQA+CQA.',
El='Elghtyelght:BAAALgAECgUJBwAAAA==.Eliicia:BAACLgAFFH8LAAIdAAUJVwTgCwAdAQAdAAUJVwTgCwAdAQAuAAQKfxQAAh0ACAkUDRomAMgBAB0ACAkUDRomAMgBAAAA.Elvwyr:BAAALgADCgQJBQAAAA==.',
Em='Embarrassed:BAAALgADCggJFwAAAA==.Emmetcullen:BAACLgAFFH8JAAIbAAQJhhVGCgA8AQAbAAQJhhVGCgA8AQAuAAQKfyAAAxsACAkgHtMTAIACABsACAkgHtMTAIACABwABAk3Cax1ALoAAAAA.Emmy:BAAALgAECgYJDgAAAA==.Emryss:BAAALgAECgIJAgAAAA==.',
En='Endo:BAAALgAECgYJCAABLgAFFAUJEQABAFsfAA==.Endorush:BAACLgAFFH8RAAQBAAUJWx/yAQB7AQABAAQJqB3yAQB7AQAIAAUJvxJHEQA1AQAMAAEJECe2AwB2AAAuAAQKfyoAAwEACQl8JXMAAOgDAAEACQl8JXMAAOgDAAgABAkNGrQ7APYAAAAA.Eneldenes:BAAALgAECgEJAQAAAA==.Enjoyer:BAAALgAECgYJEAAAAA==.',
Er='Ereitherla:BAABLgAECn8ZAAIRAAYJjwpsPgAbAQARAAYJjwpsPgAbAQAAAA==.',
Es='Eshaia:BAAALgADCgQJBAAAAA==.Espressð:BAAALgAECgIJAgAAAA==.',
Ex='Excalibear:BAABLgAECn8iAAIDAAgJvRE/MgC2AQADAAgJvRE/MgC2AQABLgAFFAUJDgACAEQaAA==.',
Ey='Eydis:BAAALgADCgUJBQAAAA==.Eyepisspeas:BAAALgADCgEJAQAAAA==.',
Ez='Ezra:BAAALgADCgkJEQAAAA==.',
Fa='Fatherjeff:BAAALgADCgkJDQAAAA==.',
Fe='Feironor:BAAALgADCgYJBgAAAA==.Feldown:BAAALgAECgYJBwAAAA==.Feyrre:BAAALgAECgMJAwAAAA==.',
Fi='Fistbroz:BAAALgAECggJCgABLgAFFAUJEgAZABISAA==.',
Fl='Flawpeacok:BAABLgAECn8YAAIQAAgJUxYbfQCJAQAQAAgJUxYbfQCJAQAAAA==.Fleredil:BAABLgAECn8pAAMFAAcJlRU0IQDZAQAFAAcJlRU0IQDZAQASAAYJPxsrDwCXAQAAAA==.Flingernle:BAAALgADCgEJAQAAAA==.Floistas:BAAALgAECgQJBAAAAA==.',
Fo='Forepray:BAAALgAECgQJBgABLgAFFAUJEQAHAMYaAA==.Forger:BAABLgAECn8bAAIUAAcJvg9kDQBKAQAUAAcJvg9kDQBKAQAAAA==.Foxfireii:BAAALgADCgMJAwAAAA==.',
Fr='Freshdk:BAACLgAFFH8NAAMQAAQJaiTpBgClAQAQAAQJaiTpBgClAQAeAAMJ9BKFAQC4AAAuAAQKfzEABBAACQnTI24MADcDABAACQnQI24MADcDAB4ABglqIj8DAKABAB8AAQljDm5BAEYAAAAA.Freÿa:BAAALgADCgYJBgABLgAECggJIQAPAPceAA==.Frostgash:BAAALgADCgcJDAAAAA==.Frostycheeks:BAABLgAECn8qAAIQAAgJoyC/DABhAgAQAAgJoyC/DABhAgAAAA==.Frostywaffle:BAAALgADCgQJBQAAAA==.',
Fu='Fubuki:BAAALgADCgEJAQAAAA==.Fudgetracks:BAAALgADCgYJBgAAAA==.Futaccine:BAABLgAECn8mAAQIAAgJXSLPGADAAgAIAAgJXSLPGADAAgAMAAEJSSGRJABeAAABAAIJRxhpKwBJAAAAAA==.Future:BAAALgAECgYJDQABLgAECggJKwAgAJElAA==.',
Ga='Gaerlan:BAAALgADCgYJBgAAAA==.Galvquodiyu:BAAALgAECgcJCQAAAA==.Garlic:BAAALgADCgEJAQAAAA==.',
Ge='Geekbarr:BAAALgADCgEJAQAAAA==.',
Gh='Ghostblades:BAACLgAFFH8OAAMQAAUJWRZdFQBOAQAQAAQJWRZdFQBOAQAeAAEJAAAvCAAAAAAuAAQKfyMAAxAACQlaIEAbANoCABAACQlaIEAbANoCAB4AAQnbHDQWADgAAAAA.Ghostdk:BAAALgAECgEJAQAAAA==.',
Gi='Gilffy:BAAALgADCgkJCgAAAA==.Gizik:BAAALgAECgIJAgABLgAFFAYJFAASAMUcAA==.',
Gl='Gloomybear:BAAALgADCgUJBQAAAA==.',
Go='Golgotterath:BAAALgAECgUJBgABLgAFFAUJDgACAEQaAA==.',
Gr='Grimzero:BAAALgADCgMJAwAAAA==.Grinny:BAABLgAECn8tAAMEAAgJJB5cDgBOAgAEAAgJJB5cDgBOAgADAAIJowMgjQBKAAAAAA==.',
Ha='Hadariel:BAAALgAECgcJCQAAAA==.Haldane:BAABLgAECn8aAAIEAAgJcArvOABhAQAEAAgJcArvOABhAQABLgAECgYJFQAcAF8jAA==.Havochunter:BAAALgAECgQJCAAAAA==.',
He='Heidegger:BAAALgAECgIJAgAAAA==.Helenkeller:BAAALgAECgIJAgAAAA==.Henderson:BAAALgADCgQJBAAAAA==.Heraois:BAAALgAECgYJEgAAAA==.Hexy:BAAALgAECgUJCAAAAA==.',
Hi='Highblood:BAAALgAECgUJBgAAAA==.',
Ho='Holytës:BAAALgADCgcJDQAAAA==.Hotea:BAAALgAECgIJBQAAAA==.',
Hp='Hpsnotdps:BAAALgAECgcJEwAAAA==.',
Hu='Hucklebeary:BAAALgADCgYJBgAAAA==.Huell:BAAALgAECgMJBAAAAA==.Hunterdh:BAABLgAECn8UAAIRAAYJMwa6TADpAAARAAYJMwa6TADpAAAAAA==.',
Hy='Hynesh:BAAALgAECgYJCwAAAA==.Hynixx:BAACLgAFFH8RAAIHAAUJxhrzBQBkAQAHAAUJxhrzBQBkAQAuAAQKfyQAAgcACAnkH70OAN4CAAcACAnkH70OAN4CAAAA.',
Ic='Icecandie:BAAALgAECgYJDQAAAA==.',
Il='Illidope:BAAALgAECgcJDAABLgAFFAUJEQAKALkgAA==.Ilostthegame:BAAALgADCgIJAgABLgAECggJJQAFAJMUAA==.',
Im='Imistmypants:BAAALgAECgUJCgAAAA==.',
In='Infinitevoid:BAAALgADCgQJBAAAAA==.Innervatez:BAABLgAFFH8LAAIXAAYJCBcfAwDrAQAXAAYJCBcfAwDrAQAAAA==.Inspectda:BAABLgAECn8VAAIPAAgJgwcSdgBxAQAPAAgJgwcSdgBxAQAAAA==.',
Io='Ionúin:BAAALgAECgQJBAAAAA==.',
Is='Issel:BAAALgAECgYJCwAAAA==.',
Iy='Iyaasu:BAAALgAECggJEwAAAA==.Iyahliea:BAAALgAECgIJAgAAAA==.',
Ja='Jaeger:BAAALgAECggJEAAAAA==.Jaekir:BAABLgAECn8cAAICAAcJwxNXNgCMAQACAAcJwxNXNgCMAQAAAA==.Jakey:BAAALgAECgYJDAAAAA==.Jakfrost:BAABLgAECn8jAAICAAgJIiTmBQDbAgACAAgJIiTmBQDbAgAAAA==.Jarten:BAABLgAECn8XAAIeAAcJ5SI8AQBJAgAeAAcJ5SI8AQBJAgAAAA==.Jaylebate:BAABLgAECn8mAAMQAAgJnRznEQArAgAQAAgJmBvnEQArAgAfAAIJIRGRIABuAAAAAA==.',
Je='Jerrenn:BAAALgAECgcJDgAAAA==.Jesseatamer:BAABLgAECn8YAAIRAAcJziS+BwB8AgARAAcJziS+BwB8AgAAAA==.',
Jo='Jolt:BAAALgADCgEJAQAAAA==.Jouska:BAAALgAECgYJBwABLgAECgcJBwAGAAAAAA==.',
Ju='Justar:BAAALgADCgIJAgAAAA==.',
Ka='Kaera:BAAALgAECgYJDgAAAA==.Kakamora:BAAALgAECgkJBwAAAA==.Kakushin:BAAALgAECgEJAQAAAA==.Kaldór:BAAALgADCgIJAgAAAA==.Kalmek:BAAALgAECggJEAAAAA==.Karne:BAAALgADCgEJAQAAAA==.Karold:BAAALgADCgUJBgAAAA==.Kartian:BAAALgAECgEJAQABLgAECgEJAQAGAAAAAA==.Kastia:BAAALgAECgIJAgAAAA==.Katrynwel:BAAALgAECgYJCQAAAA==.Katsumi:BAAALgADCgkJIAAAAA==.Kaylinne:BAAALgAECgEJAQAAAA==.',
Kh='Khainen:BAAALgAECgQJBAAAAA==.',
Ki='Killalltoday:BAABLgAECn8dAAMhAAcJqQzeCwAeAQAhAAYJbgreCwAeAQAcAAYJDRNJLgAJAQAAAA==.Kilon:BAAALgAECgEJAgAAAA==.Kirkk:BAAALgADCgkJFAAAAA==.Kixarea:BAAALgADCgkJCgABLgAECggJGwAXABkgAA==.',
Kn='Kneesweak:BAAALgAECgQJBgAAAA==.Knexx:BAAALgAECgYJDQAAAA==.Knixx:BAACLgAFFH8OAAMSAAQJ0wbCCQAiAQASAAQJ0wbCCQAiAQAiAAMJyAQLFgCCAAAuAAQKfzEABBIACQlJFZAHAA4CABIACQlJFZAHAA4CAAUABwk6GGEbAAECACIABglZEMQtADABAAAA.Knotty:BAAALgADCgYJDQAAAA==.',
Ko='Kotalyst:BAABLgAECn8dAAIaAAkJThGODQCzAQAaAAkJThGODQCzAQAAAA==.Kotastrophe:BAAALgAECgcJBwAAAA==.Koveras:BAAALgADCgkJCwAAAA==.Koyaanis:BAABLgAECn8lAAIjAAgJzBg6BwBJAgAjAAgJzBg6BwBJAgAAAA==.Koyya:BAAALgAECgUJCgAAAA==.',
Ku='Kufoo:BAABLgAECn8dAAIHAAcJBx/GBwAwAgAHAAcJBx/GBwAwAgAAAA==.Kuma:BAAALgAECgUJCQABLgAECggJKwAgAJElAA==.Kuraikage:BAAALgADCgEJAQAAAA==.Kurao:BAAALgAECgMJAwAAAA==.Kurukai:BAAALgADCgUJBgAAAA==.',
Ky='Kynlerrine:BAAALgAECgcJEAAAAA==.Kyokushin:BAAALgAECgMJAwAAAA==.',
La='Layez:BAAALgADCgUJBQABLgAECgcJHAAPALgfAA==.',
Le='Leguan:BAAALgADCgkJDQAAAA==.Lethe:BAAALgADCgUJBQABLgAFFAUJCwAdAFcEAA==.',
Li='Likestoflash:BAEALgAECgYJEAABLgAECgkJKwARAPQaAA==.Lilgeeked:BAAALgADCgYJCwAAAA==.Liliannrose:BAAALgAECgEJAQAAAA==.',
Lo='Locklove:BAAALgADCgkJCQAAAA==.Lohal:BAABLgAECn8hAAIPAAgJehiCKACMAQAPAAgJehiCKACMAQAAAA==.Lolalashay:BAAALgAECgMJBwAAAA==.Lorilock:BAAALgADCgUJBQAAAA==.Loudawn:BAABLgAECn8dAAINAAgJWwa7HgAHAQANAAgJWwa7HgAHAQAAAA==.',
Lu='Luania:BAAALgAECgEJAQAAAA==.Lupo:BAAALgAECgEJAQAAAA==.Lusucio:BAAALgAFFAIJAwAAAA==.',
Ly='Lyberrath:BAAALgADCgQJBQAAAA==.Lyeth:BAAALgAECgMJBAAAAA==.Lyna:BAAALgADCgcJBwAAAA==.',
['Lé']='Lélouch:BAAALgAECgYJBgABLgAFFAQJCQAbAIYVAA==.',
Ma='Magerthat:BAAALgADCgYJBwAAAA==.Magicaltickl:BAABLgAECn8mAAMCAAgJmRXaIgDeAQACAAgJmRXaIgDeAQAkAAMJ/ggeCwCIAAAAAA==.Magiki:BAAALgAECgEJAQAAAA==.Mamadeezy:BAAALgADCgYJDQAAAA==.Manical:BAAALgADCgkJDQAAAA==.Mashiach:BAAALgADCgcJBwABLgAFFAMJAwAGAAAAAA==.Maxgoon:BAABLgAECn8WAAIPAAcJwgzPcwB2AQAPAAcJwgzPcwB2AQAAAA==.',
Me='Megumin:BAAALgAECgUJDQABLgAECggJIgAEAIAgAA==.Mellisandria:BAAALgAECgQJBAAAAA==.Melodious:BAAALgADCgYJCQAAAA==.Merek:BAABLgAECn8dAAIaAAcJgxzjCQDtAQAaAAcJgxzjCQDtAQAAAA==.Merriska:BAACLgAFFH8FAAMDAAIJxSAtFQDBAAADAAIJxSAtFQDBAAAEAAEJFxEgRABOAAAuAAQKfxkAAwQACQlBIaAlAJACAAQABwnzIaAlAJACAAMACAm7IJsTAHUCAAEuAAUUAwkDAAYAAAAA.',
Mi='Miashadow:BAAALgADCgcJDQAAAA==.Mikeysmom:BAAALgAECgcJCwAAAA==.Misseslovett:BAAALgADCgQJBAAAAA==.Missmeow:BAAALgADCgYJBgAAAA==.Mistyd:BAACLgAFFH8PAAIlAAUJeQ4pAwD+AAAlAAUJeQ4pAwD+AAAuAAQKfzMAAiUACQnpGUwFAIoCACUACQnpGUwFAIoCAAAA.',
Mo='Monkar:BAAALgADCgMJAwAAAA==.Monkdiluffy:BAAALgADCgUJBQAAAA==.Moocifer:BAAALgAECgIJAgAAAA==.Moonstriker:BAABLgAECn8lAAIDAAgJAyayAQBoAwADAAgJAyayAQBoAwAAAA==.Morgause:BAAALgAECgYJDAAAAA==.Morijinn:BAAALgAECgQJBQAAAA==.Morllan:BAAALgAECgEJAgAAAA==.Mortyxp:BAAALgADCgIJAgAAAA==.Mowenudown:BAAALgAECgEJAQAAAA==.',
Mu='Muirdin:BAAALgAECgYJEgAAAA==.',
Mv='Mvp:BAAALgADCgYJBgAAAA==.',
['Má']='Máelyss:BAAALgAECgQJBgAAAA==.',
['Må']='Mångix:BAAALgAECgIJAgAAAA==.',
['Mé']='Mélusine:BAABLgAECn8dAAMVAAgJdR78AwAKAgAVAAgJXh38AwAKAgAHAAUJNRtlTAB0AQAAAA==.',
['Mï']='Mïsterlovett:BAAALgADCgkJFwABLgAECggJIQAPAPceAA==.',
Na='Naanomage:BAAALgAECgMJBgAAAA==.Nagato:BAAALgADCgcJBwAAAA==.',
Ne='Necrotoxin:BAABLgAECn8hAAMPAAgJ9x5LNQA3AgAPAAcJ9x5LNQA3AgAOAAEJAADvXABYAAAAAA==.',
Ni='Nibble:BAAALgADCgQJBAAAAA==.Nightsever:BAABLgAECn8YAAMIAAkJ4hvkIQCGAgAIAAkJbRnkIQCGAgABAAUJBCGqJgCLAQAAAA==.Nirath:BAABLgAECn8cAAIKAAcJygn0BQBFAQAKAAcJygn0BQBFAQAAAA==.',
No='Noiire:BAAALgAECgIJAgABLgAFFAUJCwAdAFcEAA==.Nopal:BAAALgADCgcJDAAAAA==.Nopriest:BAACLgAFFH8IAAISAAMJrSGeCAA4AQASAAMJrSGeCAA4AQAuAAQKfysAAhIACAmjJRgBAAIDABIACAmjJRgBAAIDAAAA.Notixx:BAAALgADCgQJBAAAAA==.Notprepared:BAABLgAECn8bAAIBAAgJFA45CwCJAQABAAgJFA45CwCJAQAAAA==.Nottisdemon:BAAALgAECgcJDQAAAA==.',
Nu='Nuggy:BAAALgAECgUJBQAAAA==.Nullfox:BAAALgADCgUJBQAAAA==.',
Oa='Oakly:BAABLgAECn8eAAIXAAcJlxrLEwDpAQAXAAcJlxrLEwDpAQAAAA==.',
On='Onaroll:BAAALgAFFAIJBAABLgAFFAUJDgAXAEIXAA==.',
Oo='Ooyagoddess:BAAALgAECgEJAwAAAA==.',
Oy='Oya:BAAALgADCgIJAgAAAA==.',
Pa='Pacamonk:BAAALgAECgUJEQAAAA==.Pacifer:BAAALgAECgEJAQAAAA==.Pann:BAAALgADCgkJDwABLgAECgMJBgAGAAAAAA==.Pauon:BAAALgADCgcJBwAAAA==.Pawpatine:BAABLgAECn8ZAAIbAAYJ0RotFwBbAQAbAAYJ0RotFwBbAQAAAA==.Pawsa:BAABLgAECn8YAAMZAAYJoRJIHwDsAAAZAAYJJRJIHwDsAAAaAAMJWQ+bagCYAAAAAA==.Pawthetic:BAACLgAFFH8OAAIXAAUJQhfYCQA6AQAXAAUJQhfYCQA6AQAuAAQKfyYAAhcACQkEIT0DAGEDABcACQkEIT0DAGEDAAAA.',
Pe='Peelforheals:BAABLgAECn8bAAMiAAcJuxUYHAC1AQAiAAcJuxUYHAC1AQASAAUJ3geYQADzAAAAAA==.Penguindemic:BAABLgAECn8XAAIPAAcJFSYMHACtAgAPAAcJFSYMHACtAgAAAA==.Pep:BAABLgAECn8cAAMZAAgJsRqgEwBTAgAZAAgJsRqgEwBTAgAjAAEJUwMNcwAgAAAAAA==.Pephunt:BAAALgADCgkJCQAAAA==.Pepperoni:BAAALgADCgQJBAAAAA==.Petruccius:BAAALgAECgUJBQAAAA==.Pewpewlepew:BAAALgAECgYJCAAAAA==.',
Ph='Phaedesana:BAAALgADCgkJCQABLgAECgcJBwAGAAAAAA==.Phaeku:BAAALgAECgcJBwAAAA==.Phòenix:BAAALgADCgkJCQAAAA==.',
Pi='Pinksparklez:BAAALgAECgEJAQAAAA==.',
Pl='Plaguedr:BAAALgAECgEJAQAAAA==.',
Po='Porbles:BAAALgADCgcJBwAAAA==.Porklamb:BAAALgAECgIJAwAAAA==.',
Pr='Prey:BAAALgADCgEJAQAAAA==.Prospa:BAAALgADCgUJBQAAAA==.Prumper:BAACLgAFFH8FAAICAAQJ5wYYPQDXAAACAAQJ5wYYPQDXAAAuAAQKfy8AAgIACAnAHpkUADYCAAIACAnAHpkUADYCAAAA.',
Py='Pyric:BAAALgAECgEJAgAAAA==.',
Qu='Quesoblanco:BAAALgADCgcJCgAAAA==.',
Qy='Qybxboogiedk:BAAALgAECgMJAwAAAA==.',
Ra='Raghallov:BAAALgADCggJCQAAAA==.Rakshash:BAAALgAECgIJAgAAAA==.Ramzey:BAABLgAECn8hAAIQAAgJNB2kOQBQAgAQAAgJNB2kOQBQAgAAAA==.Rawnis:BAAALgAECgEJAQAAAA==.Raylëigh:BAAALgADCgYJBgAAAA==.',
Re='Redbearon:BAAALgAECgEJAQAAAA==.Redroger:BAAALgADCgQJBQAAAA==.Regena:BAABLgAECn8lAAMFAAgJkxSDDgC6AQAFAAgJkxSDDgC6AQAiAAUJcgU3OgDWAAAAAA==.Remorse:BAACLgAFFH8NAAIUAAUJqxH2BgAXAQAUAAUJqxH2BgAXAQAuAAQKfy0AAhQACQnrGg8DAGYCABQACQnrGg8DAGYCAAAA.Required:BAAALgAECgUJBwABLgAFFAIJAwAGAAAAAA==.Retro:BAAALgAECgYJEQAAAA==.',
Rh='Rhysara:BAAALgAECgEJAQAAAA==.',
Ri='Rikatree:BAABLgAECn8bAAIXAAgJGSCoBQDDAgAXAAgJGSCoBQDDAgAAAA==.Rim:BAABLgAECn8nAAIcAAgJ3x9rAwDZAgAcAAgJ3x9rAwDZAgAAAA==.Rinaren:BAAALgADCgcJCAAAAA==.Risque:BAABLgAECn8eAAICAAgJGB1rNAChAgACAAgJGB1rNAChAgAAAA==.',
Ro='Ronard:BAACLgAFFH8HAAIQAAIJrhsORQC4AAAQAAIJrhsORQC4AAAuAAQKfy4AAhAACQmRI4QGAG8DABAACQmRI4QGAG8DAAAA.Ronfar:BAACLgAFFH8JAAIhAAQJ6RLwAgDRAAAhAAQJ6RLwAgDRAAAuAAQKfzEAAiEACAlVIt8AAMUCACEACAlVIt8AAMUCAAAA.',
Ru='Rukidingme:BAAALgADCgcJDgAAAA==.Runehammer:BAAALgADCgMJAwAAAA==.Ruttisðir:BAAALgAECgYJBgAAAA==.',
Rw='Rw:BAAALgAECgEJAQAAAA==.',
Ry='Ryhorn:BAABLgAECn8eAAIEAAYJWgkFWgADAQAEAAYJWgkFWgADAQAAAA==.Ryno:BAAALgADCgUJBQAAAA==.Ryomensukuna:BAAALgAECgMJAwAAAA==.Ryujin:BAAALgAECggJEQAAAA==.',
Sa='Sadcraig:BAAALgADCgYJBgAAAA==.Salo:BAAALgAECgMJBAAAAA==.Sanazenet:BAAALgAECgQJBAAAAA==.Saronas:BAAALgADCggJCQABLgAECgcJFwAeAOUiAA==.',
Sc='Scootypuffsr:BAAALgAECgYJDgAAAA==.Scootyshooty:BAAALgADCgYJBgAAAA==.Scrap:BAABLgAECn8WAAIZAAcJFxM/LAB+AQAZAAcJFxM/LAB+AQAAAA==.Scubasuiit:BAABLgAECn8dAAQXAAgJdhy1JQAiAgAXAAcJ1By1JQAiAgANAAYJ+R56HwADAgAlAAEJGQaUNQAfAAAAAA==.',
Se='Segarth:BAAALgAECgcJCQAAAA==.Selen:BAABLgAECn8mAAIDAAgJZR+pBACrAgADAAgJZR+pBACrAgAAAA==.Seleste:BAAALgADCgYJCAAAAA==.Seråphiel:BAAALgAECgQJDgAAAA==.Seswatha:BAACLgAFFH8OAAICAAUJRBpxGwBdAQACAAUJRBpxGwBdAQAuAAQKfyIAAgIACQmfIQwEAAADAAIACQmfIQwEAAADAAAA.',
Sh='Shadowbaron:BAAALgADCgkJGQAAAA==.Shadowsnek:BAAALgAECgEJAQAAAA==.Shaltear:BAAALgAECgYJCAAAAA==.Shamandroo:BAAALgAECggJEAABLgAFFAUJEQADACwYAA==.Shamdi:BAAALgADCgYJBgAAAA==.Shenzu:BAAALgAECgYJDgAAAA==.Shmongus:BAAALgADCgYJBgABLgAECgYJEAAGAAAAAA==.Shocktop:BAAALgAECgUJDAAAAA==.Shortfuse:BAAALgAECgEJAQABLgAECgUJDAAGAAAAAA==.Shz:BAAALgAECgEJAQABLgAECgQJCAAGAAAAAA==.Shådowfire:BAAALgADCgkJFgAAAA==.Shìft:BAABLgAECn8cAAIXAAcJyxh2EAANAgAXAAcJyxh2EAANAgAAAA==.',
Si='Siercy:BAAALgADCgMJBQAAAA==.Sightofhand:BAAALgADCgYJBwAAAA==.Simplysauced:BAAALgAECgQJCwABLgAECgkJKAANALAdAA==.',
Sk='Skylér:BAAALgADCgkJCQAAAA==.',
Sl='Slighted:BAAALgAECgMJBgABLgAECgYJCwAGAAAAAA==.Sliizzy:BAAALgADCgMJAwAAAA==.Slimydruid:BAABLgAECn8WAAIlAAYJvB88BwB6AQAlAAYJvB88BwB6AQAAAA==.Slizz:BAAALgADCgYJCwAAAA==.Slizzard:BAAALgADCgYJDAAAAA==.Slow:BAABLgAECn8rAAQgAAgJkSWgAgBmAgACAAgJjyB5LQC8AgAgAAYJsCKgAgBmAgAkAAQJXh9EAgB6AQAAAA==.',
Sm='Smaltownlock:BAAALgADCgMJAwAAAA==.Smo:BAAALgADCgYJBgAAAA==.Smokze:BAAALgAECgYJCgAAAA==.Smug:BAAALgAECggJDgAAAA==.',
So='Sonicberger:BAAALgADCgQJBAABLgAECgcJGAAQAIIbAA==.Sonicbergger:BAAALgAECgQJBAABLgAECgcJGAAQAIIbAA==.Sonicpoe:BAAALgADCgkJCQABLgAECgcJGAAQAIIbAA==.Sonícberger:BAABLgAECn8YAAMQAAcJghsqKgCTAQAQAAcJghsqKgCTAQAfAAEJkQmTLwAdAAAAAA==.Soulcaliber:BAAALgADCgEJAQAAAA==.',
St='Stain:BAAALgAECgQJBQAAAA==.Stepdragon:BAAALgADCgYJBgAAAA==.Stith:BAAALgADCgIJAgAAAA==.Stkinbck:BAABLgAECn8ZAAIdAAYJ5wxuFQAvAQAdAAYJ5wxuFQAvAQAAAA==.Stonehenge:BAABLgAECn8VAAIcAAYJXyMsFwBcAgAcAAYJXyMsFwBcAgAAAA==.Stonepalm:BAAALgADCgMJAwAAAA==.Stratan:BAAALgAECgQJBQAAAA==.',
Su='Suffer:BAAALgAECgQJCQABLgAECggJKwAgAJElAA==.Sundermere:BAAALgAECgEJAQAAAA==.Supercat:BAAALgAECgQJBwAAAA==.Surai:BAAALgADCgUJBQAAAA==.Surf:BAABLgAECn8VAAIEAAcJiSDSIwCZAgAEAAcJiSDSIwCZAgAAAA==.',
Sw='Swanky:BAAALgAECggJCwAAAA==.Swankydranky:BAACLgAFFH8SAAQZAAUJEhINBwAnAQAZAAQJlQwNBwAnAQAaAAUJJwxEEAD+AAAjAAEJLgBfGgATAAAuAAQKfy8AAxoACQmHGlESAIECABoACQnBFlESAIECABkACAlmG3UTAFUCAAAA.',
Sy='Sylvia:BAAALgAECgMJBAAAAA==.Symphania:BAAALgAECgYJCwAAAA==.',
['Sä']='Sätansangel:BAAALgAECgEJAQAAAA==.',
Ta='Tabbz:BAABLgAECn8mAAMbAAgJSxo7CAAcAgAbAAgJSxo7CAAcAgAcAAEJBQeppQAqAAAAAA==.Tahl:BAAALgADCgMJAwAAAA==.Taiils:BAAALgADCgQJBAAAAA==.Tallael:BAAALgADCgcJBwAAAA==.Tallyhochick:BAABLgAECn8XAAIRAAcJdAjgMwBCAQARAAcJdAjgMwBCAQAAAA==.Taman:BAABLgAECn8YAAMbAAcJOBalKADPAQAbAAcJOBalKADPAQAcAAYJaxVUMAD+AAAAAA==.Tasana:BAAALgADCgYJBgAAAA==.Taylerswift:BAAALgAECgQJBwAAAA==.',
Te='Telkon:BAAALgADCgYJBgAAAA==.Tellesto:BAABLgAECn8rAAMmAAkJWhz2AgByAgAmAAkJqRr2AgByAgARAAIJhhHfowCDAAAAAA==.',
Th='Thadox:BAAALgADCgIJAgAAAA==.Thatdh:BAAALgADCgQJBAAAAA==.Thebestname:BAAALgADCgcJBwAAAA==.Thebigonion:BAAALgADCgkJFgAAAA==.',
Ti='Tinydh:BAAALgADCgYJBgAAAA==.Tinyfu:BAABLgAECn8dAAMaAAcJtRvsDgCgAQAaAAcJtRvsDgCgAQAZAAEJhRnkPQBLAAAAAA==.Tinymonk:BAAALgADCgIJAgABLgAECggJIAARANYgAA==.Tinyriggo:BAAALgADCgYJBgAAAA==.Tinyshift:BAAALgAECgYJBgAAAA==.Tinytamer:BAABLgAECn8gAAMRAAgJ1iAIDwDDAgARAAgJySAIDwDDAgAmAAQJhw6vHADFAAAAAA==.',
To='Toko:BAACLgAFFH8SAAIRAAUJwiAtAgB9AQARAAUJwiAtAgB9AQAuAAQKfyMAAxEACQkmIuYIAAUDABEACQkmIuYIAAUDACcAAQmjCuyLAC8AAAAA.Tomblord:BAABLgAECn8fAAMeAAgJphsnBAAnAgAeAAgJphsnBAAnAgAfAAMJGQqJQABLAAAAAA==.Toogga:BAAALgADCgcJDgAAAA==.',
Tr='Treeheals:BAAALgAECgIJAgAAAA==.Tristaine:BAAALgADCgYJBgABLgAECgMJBAAGAAAAAA==.Truepatriot:BAACLgAFFH8FAAIDAAMJ9w1QEwDYAAADAAMJ9w1QEwDYAAAuAAQKfyYAAwMACAmoExIyALcBAAMACAmoExIyALcBABYABQnVEsURAOgAAAAA.Truexlord:BAABLgAECn8UAAIQAAYJSww3XgDsAAAQAAYJSww3XgDsAAAAAA==.Truthes:BAAALgAECgIJAgABLgAECgcJHAAPALgfAA==.Truthez:BAAALgADCgMJBgABLgAECgcJHAAPALgfAA==.Truths:BAAALgAECgIJAgABLgAECgcJHAAPALgfAA==.Truthsx:BAABLgAECn8cAAMPAAcJuB/kMQBkAQAPAAUJchrkMQBkAQATAAUJzh/tBQAaAQAAAA==.',
Tw='Twin:BAAALgAECgIJAgAAAA==.',
Ty='Tyg:BAAALgAECgMJAwAAAA==.Tygerkillz:BAAALgAECgIJAgAAAA==.Tylaatape:BAAALgAECgMJAwAAAA==.Tyraell:BAABLgAECn8jAAMDAAgJpx0hBgCBAgADAAgJpx0hBgCBAgAEAAQJnwc77QC1AAAAAA==.Tyrelan:BAAALgADCgMJAwAAAA==.',
['Tõ']='Tõko:BAABLgAECn8aAAIfAAgJECFcBQDsAgAfAAgJECFcBQDsAgABLgAFFAUJEgARAMIgAA==.',
Ud='Udor:BAAALgAECgYJCgAAAA==.',
Um='Umbrae:BAABLgAECn8gAAIFAAcJLxxpCQASAgAFAAcJLxxpCQASAgAAAA==.',
Up='Upies:BAAALgAECgQJBQAAAA==.',
Us='Usgasdanelv:BAAALgAECgUJCwAAAA==.',
Uz='Uzala:BAAALgAECgMJBQAAAA==.',
Va='Valzanaya:BAAALgADCgYJBgAAAA==.Vanasmine:BAAALgAECgMJBAAAAA==.Vanleiden:BAAALgAECgQJBgAAAA==.Varael:BAAALgADCgIJAgAAAA==.Varielqt:BAAALgAECgMJAwAAAA==.Varilla:BAABLgAECn8VAAIPAAcJNBnCPAA8AQAPAAcJNBnCPAA8AQAAAA==.',
Ve='Veera:BAABLgAECn8eAAIbAAgJug7bFQBnAQAbAAgJug7bFQBnAQAAAA==.Vendyr:BAABLgAECn8ZAAQTAAgJoyHxBwDOAQAPAAcJQx4uLQBZAgATAAYJYhjxBwDOAQAOAAIJ8AsXYABPAAAAAA==.',
Vi='Vikadii:BAAALgADCgIJAgAAAA==.Viperjaxx:BAAALgADCgEJAQAAAA==.',
Vo='Voidbloom:BAAALgADCgYJBgAAAA==.Voodruid:BAAALgADCggJCQAAAA==.Vorgol:BAABLgAECn8aAAIVAAkJShYQCAA4AgAVAAkJShYQCAA4AgAAAA==.Voìd:BAAALgAECgQJBQAAAA==.',
Vy='Vyeria:BAABLgAECn8hAAIEAAcJjhLjZAC3AQAEAAcJjhLjZAC3AQAAAA==.Vyleera:BAAALgADCgEJAgAAAA==.Vynloran:BAACLgAFFH8LAAIEAAQJfApfFAAwAQAEAAQJfApfFAAwAQAuAAQKfxwAAgQACAmzHaojAJoCAAQACAmzHaojAJoCAAAA.',
We='Westerin:BAABLgAECn8cAAIOAAgJmxi6AgDcAQAOAAgJmxi6AgDcAQAAAA==.',
Wi='Wildchild:BAAALgADCgMJBgAAAA==.Wimateeka:BAABLgAECn8cAAQWAAcJuByvBwCeAQAWAAcJuByvBwCeAQADAAUJxRIJYQD4AAAEAAQJlw2M3QDRAAAAAA==.Windfury:BAAALgAECgYJCgABLgAECggJKwAgAJElAA==.Windigo:BAAALgAECgYJDwAAAA==.Winginit:BAAALgAECgUJCQABLgAFFAUJDgAXAEIXAA==.',
Wo='Wolfswarlock:BAAALgADCgMJAwAAAA==.Wooqles:BAAALgADCgcJDQAAAA==.',
Xa='Xaltorian:BAAALgADCgQJBAAAAA==.Xantus:BAAALgAECgQJBwAAAA==.',
Xi='Xiaoláng:BAAALgAECgYJCwAAAA==.Xiraxes:BAAALgAECgEJAQAAAA==.',
Ya='Yachak:BAAALgADCgcJBwABLgAECgcJIQAEAOAWAA==.',
Ye='Yespaladin:BAAALgAECgYJBwABLgAFFAMJCAASAK0hAA==.',
Yi='Yiddosh:BAAALgAECgMJCQAAAA==.',
Yo='Yogí:BAACLgAFFH8OAAIcAAUJJh3UAgDOAQAcAAUJJh3UAgDOAQAuAAQKfxcAAxwACAk5I94FABQDABwACAk5I94FABQDACEAAQk+A9wuACoAAAAA.Yonamee:BAAALgADCgYJDAAAAA==.Yozomoto:BAAALgAECgQJBAAAAA==.',
Yu='Yumsumwum:BAAALgAFFAMJAwAAAA==.',
Za='Zacian:BAAALgADCgMJAwAAAA==.Zalandria:BAAALgAECgYJDQAAAA==.Zanalia:BAAALgAECgMJBAAAAA==.',
Ze='Zeffie:BAAALgAECgQJBgAAAA==.Zelxari:BAABLgAECn8WAAIPAAcJNwrWOQBGAQAPAAcJNwrWOQBGAQAAAA==.Zenithaunter:BAAALgAECgEJAQAAAA==.Zensho:BAAALgAECgYJCQAAAA==.',
Zi='Zipsion:BAABLgAECn8ZAAIRAAgJVyB8DAA8AgARAAgJVyB8DAA8AgAAAA==.Zithen:BAAALgAFFAEJAQAAAA==.Zivver:BAABLgAECn8mAAIUAAgJ1iG0AQCwAgAUAAgJ1iG0AQCwAgAAAA==.',
Zo='Zorazig:BAAALgADCgIJAgAAAA==.',
Zx='Zxcycxz:BAAALgAECgMJBAAAAA==.',
['År']='Årikard:BAABLgAECn8XAAIDAAcJkR4IDAAXAgADAAcJkR4IDAAXAgAAAA==.',
['Çh']='Çharmy:BAAALgAECggJCAAAAA==.',
['Çi']='Çinderella:BAAALgADCgYJBgAAAA==.',
['Éd']='Édelgard:BAAALgAECgMJBAAAAA==.',
['Üt']='Üther:BAABLgAECn8iAAMEAAgJgCA9FAAZAgAEAAgJgCA9FAAZAgAWAAEJgxaeJABDAAAAAA==.',
['ßu']='ßubbleøseven:BAAALgAECgEJAQAAAA==.',
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
