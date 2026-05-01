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

local lookup = {'DeathKnight-Unholy','DeathKnight-Frost','Evoker-Augmentation','Mage-Frost','Shaman-Restoration','Paladin-Holy','Unknown-Unknown','Monk-Brewmaster','Hunter-Marksmanship','Paladin-Retribution','Druid-Guardian','Rogue-Subtlety','Warlock-Demonology','Hunter-Survival','Monk-Windwalker','DemonHunter-Devourer','DemonHunter-Vengeance','Hunter-BeastMastery','Druid-Balance','Druid-Restoration','Warlock-Destruction','Warlock-Affliction','Mage-Arcane','Mage-Fire','Shaman-Elemental','Druid-Feral','Rogue-Outlaw','Paladin-Protection','DeathKnight-Blood','Warrior-Arms','Evoker-Preservation','Priest-Holy','Priest-Discipline','Warrior-Protection','Monk-Mistweaver','Evoker-Devastation','Warrior-Fury','Shaman-Enhancement','Priest-Shadow','DemonHunter-Havoc',}
local provider = {region='US',realm='ArgentDawn',name='US',type='weekly',zone=46,date='2026-05-01',data={Ad='Adaine:BAAALgADCgUJBQAAAA==.Adriana:BAAALgAECgYJEAAAAA==.Adru:BAAALgAECgYJDgAAAA==.',
Ae='Aeglos:BAACLgAFFH8FAAMBAAMJ4hmWKgATAQABAAMJVxmWKgATAQACAAEJGxIyBgBXAAAuAAQKfx0AAwEACAkKIsAWAPMCAAEACAkKIsAWAPMCAAIABAnbH1IJAEYBAAAA.Aelera:BAAALgADCgkJDgAAAA==.Aentharion:BAABLgAECn8XAAIDAAYJlxgHEgB4AQADAAYJlxgHEgB4AQAAAA==.Aer:BAAALgADCgUJBQAAAA==.Aertimis:BAAALgADCgMJAwAAAA==.Aevielyn:BAAALgADCgQJCAAAAA==.',
Ag='Aguth:BAAALgADCgMJAwAAAA==.',
Ai='Aileen:BAAALgAECggJEgAAAA==.Airiya:BAAALgAECgUJBAAAAA==.',
Aj='Ajami:BAAALgADCgIJAgAAAA==.',
Al='Alacite:BAAALgAECgcJEwAAAA==.Aleyah:BAAALgAECgcJAgAAAA==.Alisonia:BAAALgADCgcJEQAAAA==.Alitikar:BAAALgADCgIJAgAAAA==.Allamura:BAAALgAECgUJBQAAAA==.Alleximage:BAABLgAECn8YAAIEAAgJ2xc0UwA+AgAEAAgJ2xc0UwA+AgAAAA==.Alorren:BAABLgAECn8YAAIFAAcJ5g9yHQB4AQAFAAcJ5g9yHQB4AQAAAA==.Althea:BAAALgADCgQJBAAAAA==.Alynia:BAAALgAECggJCAAAAA==.Alyssa:BAAALgAECgUJBQAAAA==.',
Am='Amodegas:BAABLgAECn8XAAIGAAgJ5yBgCADoAgAGAAgJ5yBgCADoAgAAAA==.Amonk:BAAALgAECgQJBwAAAA==.Amonra:BAAALgAECgMJAwAAAA==.Amordil:BAAALgADCgQJBAAAAA==.Amynrar:BAAALgAECgMJAwAAAA==.',
An='Ancalagrond:BAAALgAECgMJBAAAAA==.Andrâste:BAAALgADCgEJAQAAAA==.Anecia:BAAALgADCgkJDwABLgAECgUJDQAHAAAAAA==.Animos:BAAALgADCgYJBgAAAA==.Annehathaway:BAAALgAECgEJAQAAAA==.Anothercaion:BAAALgAECgUJDQAAAA==.Anthor:BAAALgADCgMJAwAAAA==.Antiihr:BAACLgAFFH8bAAIIAAYJiSRWAAB6AgAIAAYJiSRWAAB6AgAuAAQKfzEAAggACQn3JN8AAL4DAAgACQn3JN8AAL4DAAAA.',
Ap='Apix:BAAALgAECgEJAQABLgAECggJHwAJAMcbAA==.',
Ar='Arcaisme:BAAALgAECgYJDQAAAA==.Arcticsnow:BAAALgAECgUJDQAAAA==.Arkose:BAAALgAECgUJCAAAAA==.Arkädia:BAAALgADCgkJDgAAAA==.Armistice:BAABLgAECn8XAAIKAAgJPiE+EwD5AgAKAAgJPiE+EwD5AgAAAA==.Artanos:BAAALgAECgQJBQAAAA==.Artiazana:BAAALgADCgEJAgAAAA==.',
As='Ashlyngrace:BAAALgAECgIJAgABLgAECggJHQAFAKMfAA==.Ashlynne:BAABLgAECn8dAAIFAAgJox/YCQDbAgAFAAgJox/YCQDbAgAAAA==.Ashlynnemia:BAAALgAECgYJBwAAAA==.Ashvara:BAAALgADCggJEwAAAA==.Asora:BAAALgAECgYJDgAAAA==.Aspect:BAAALgAECgcJCQAAAA==.Aspensong:BAABLgAECn8XAAILAAYJNhySBwBwAQALAAYJNhySBwBwAQAAAA==.Astracious:BAAALgADCggJEgAAAA==.',
At='Atax:BAABLgAECn8XAAIMAAYJjhXwEQBVAQAMAAYJjhXwEQBVAQAAAA==.Athená:BAAALgAECgYJCAAAAA==.Atheum:BAAALgADCgQJBAAAAA==.',
Au='Auralyn:BAAALgADCgcJDgAAAA==.Aurelitrasza:BAAALgADCgUJBQAAAA==.',
Av='Avicena:BAAALgAECgUJCAAAAA==.Avicii:BAAALgADCgUJCgAAAA==.Avrice:BAAALgAECgEJAQAAAA==.',
Ax='Axfrosty:BAAALgADCgQJBAAAAA==.Axiona:BAAALgADCgIJBwAAAA==.',
Ay='Ayakia:BAAALgAECgYJCgAAAA==.Ayaku:BAAALgAECgIJAgAAAA==.',
Az='Azuraa:BAAALgADCgUJCAAAAA==.',
Ba='Badshot:BAAALgAECgYJDwAAAA==.Baiogg:BAABLgAECn8YAAINAAcJLwV3TQAIAQANAAcJLwV3TQAIAQAAAA==.Baldord:BAAALgADCgMJBAAAAA==.Balthromaww:BAAALgAECgYJBwAAAA==.Balung:BAAALgAECgQJBgAAAA==.Bambu:BAAALgAECgYJBwAAAA==.Bamevoker:BAAALgAECgMJAwABLgAECgYJBwAHAAAAAA==.Bariggs:BAABLgAECn8WAAIOAAcJryTFBADGAgAOAAcJryTFBADGAgAAAA==.Barilia:BAAALgADCgYJCAAAAA==.',
Be='Bearlyalive:BAAALgADCgMJAwAAAA==.Beladra:BAAALgADCgUJCwAAAA==.Belekor:BAAALgAECgYJCQAAAA==.Beltayn:BAAALgAECgYJCwAAAA==.Ben:BAABLgAECn8aAAIPAAkJehYqFABNAgAPAAkJehYqFABNAgAAAA==.Beriadan:BAAALgAECgIJAgAAAA==.Bevee:BAAALgAECgMJBgAAAA==.Bewitchin:BAAALgAECgEJAQAAAA==.',
Bi='Bigponch:BAAALgADCgEJAQAAAA==.Birst:BAAALgADCggJBAAAAA==.Bisque:BAAALgAECgEJAQAAAA==.',
Bl='Bladesrus:BAAALgAECgIJBAAAAA==.Blaithe:BAAALgAECgEJAQAAAA==.Bleddwen:BAAALgAECgQJCwAAAQ==.Bliggix:BAAALgADCgQJBAAAAA==.Blrsama:BAAALgADCgUJBgAAAA==.',
Bo='Bodok:BAABLgAECn8VAAMQAAYJexPuPgDrAAAQAAYJexPuPgDrAAARAAEJvwXRGQArAAAAAA==.Bohrnir:BAABLgAECn8jAAIFAAgJtx24DwD6AQAFAAgJtx24DwD6AQAAAA==.Boomonster:BAAALgADCgcJBwAAAA==.Boüh:BAAALgAECgYJCwAAAA==.',
Br='Brackiss:BAAALgAECgEJAQAAAA==.Brokiinn:BAACLgAFFH8FAAISAAIJ9BFhFQCvAAASAAIJ9BFhFQCvAAAuAAQKfxoAAhIACAl1GfMbAF8CABIACAl1GfMbAF8CAAAA.Brutalix:BAAALgADCgYJDQAAAA==.Brynda:BAAALgADCgQJBAAAAA==.',
Bu='Budikah:BAAALgAECgQJAgAAAA==.Burd:BAAALgADCgcJBwAAAA==.Burmeister:BAABLgAECn8VAAMTAAYJ0wjWIgDpAAATAAYJ0wjWIgDpAAAUAAYJpgdfPADgAAAAAA==.Burnadine:BAAALgAECgQJCgAAAA==.Burnswhnpee:BAABLgAECn8VAAQVAAgJzRMhHABtAQAVAAYJ5xIhHABtAQANAAYJig6+ZQDFAAAWAAIJVAjEIgBnAAAAAA==.Burtelby:BAAALgADCgYJBgAAAA==.',
['Bû']='Bûrd:BAABLgAECn8jAAQXAAgJdhHmAQDCAQAXAAgJCBDmAQDCAQAYAAYJCgxyBwAKAQAEAAUJsQvAAwH0AAAAAA==.',
Ca='Cadsuàne:BAAALgADCgUJCAAAAA==.Caliie:BAABLgAECn8XAAMFAAYJ1QNPaQDqAAAFAAYJ1QNPaQDqAAAZAAUJZwO2NgCYAAAAAA==.Callira:BAAALgAECgUJEAAAAA==.Cambiare:BAAALgADCgYJCgAAAA==.Canaandra:BAAALgADCgkJBwAAAA==.Captclamslam:BAABLgAECn8UAAMLAAgJ2wojDwDHAAALAAcJwwojDwDHAAAaAAIJVQkjHQA6AAAAAA==.Carolline:BAAALgADCgkJCgAAAA==.Catherinecay:BAAALgADCgcJBwAAAA==.',
Ce='Cereania:BAAALgAECgYJDQAAAA==.Cerrabell:BAAALgADCgcJBwAAAA==.',
Ch='Charzzard:BAAALgADCgEJAQAAAA==.Checksmix:BAAALgAECgEJAQAAAA==.Chintakari:BAABLgAECn8YAAMSAAcJ5RNgJwB6AQASAAcJ5RNgJwB6AQAOAAEJLwe1MAAxAAAAAA==.Chlorofill:BAAALgAECgcJCQAAAA==.Chronologic:BAAALgAECgYJEAAAAA==.',
Co='Cocidiae:BAAALgAECgEJAwAAAA==.Confusious:BAACLgAFFH8GAAIFAAMJkBnyFQDaAAAFAAMJkBnyFQDaAAAuAAQKfygAAwUACQmTFYEUAMcBAAUACQmTFYEUAMcBABkAAQloBPpYACYAAAAA.Coree:BAABLgAECn8oAAIbAAYJ1w6HBQAYAQAbAAYJ1w6HBQAYAQAAAA==.Cornflower:BAAALgAECgcJEAAAAA==.Corvaan:BAABLgAECn8bAAIQAAgJ1RH4HgB5AQAQAAgJ1RH4HgB5AQAAAA==.',
Cr='Creg:BAABLgAECn8XAAIQAAYJjiIgEgDbAQAQAAYJjiIgEgDbAQAAAA==.Crowbarr:BAAALgADCgUJBQAAAA==.Cryostatic:BAAALgAECgMJAwABLgAECgYJFQAcAEIJAA==.',
Cu='Cultel:BAABLgAECn8qAAIRAAgJyx4cAgAyAgARAAgJyx4cAgAyAgAAAA==.',
Cy='Cyendia:BAABLgAECn8UAAIFAAYJ2hwIEQDsAQAFAAYJ2hwIEQDsAQAAAA==.Cyer:BAAALgAECgQJBgAAAA==.',
Da='Daddyraz:BAABLgAECn8TAAIQAAcJ+BacZAB0AQAQAAcJ+BacZAB0AQAAAA==.Dakan:BAAALgADCgkJFgAAAA==.Daphcelyn:BAAALgAECgEJAgAAAA==.Dariusz:BAAALgAECgQJBAAAAA==.Darkalen:BAABLgAECn8iAAIdAAgJeBMjCwBeAQAdAAgJeBMjCwBeAQAAAA==.Darklodus:BAAALgADCgcJEwAAAA==.Darriuss:BAABLgAECn8YAAIKAAUJuQKjkACGAAAKAAUJuQKjkACGAAAAAA==.Dathea:BAAALgADCgYJBgAAAA==.Davìd:BAAALgAECgEJAQAAAA==.Dawnmist:BAAALgAECgMJBgAAAA==.Daxetandh:BAAALgAECgIJBAAAAA==.Daxetanir:BAAALgADCgMJAwABLgAFFAIJBQAZABEaAA==.Daxetans:BAACLgAFFH8FAAIZAAIJERqBFACpAAAZAAIJERqBFACpAAAuAAQKfzEAAxkACQkUIfMAAC8DABkACQkUIfMAAC8DAAUABwk+DN5GAGYBAAAA.',
De='Deadmoose:BAABLgAECn8qAAIBAAkJRxPqFQALAgABAAkJRxPqFQALAgAAAA==.Deathb:BAAALgADCgkJIAAAAA==.Deathjingle:BAABLgAECn8kAAMdAAkJDxuXBQDYAQABAAkJmBd7RwAeAgAdAAYJZCKXBQDYAQAAAA==.Deecayed:BAABLgAECn8UAAIKAAYJahXnRgA1AQAKAAYJahXnRgA1AQAAAA==.Deecoy:BAAALgAECgYJDgAAAA==.Deestroyer:BAAALgAECgUJCgAAAA==.Deetermined:BAABLgAECn8jAAIFAAgJQh6TBAC1AgAFAAgJQh6TBAC1AgAAAA==.Delion:BAAALgADCgIJAgAAAA==.Demhuloo:BAAALgAECgQJBQAAAA==.Demonburp:BAABLgAECn8iAAIQAAgJNCHgBACWAgAQAAgJNCHgBACWAgAAAA==.Denchy:BAABLgAECn8WAAIeAAYJVgWYIQDgAAAeAAYJVgWYIQDgAAAAAA==.Dendris:BAAALgADCgcJCwAAAA==.Desetraz:BAAALgAECgYJCwAAAQ==.Deval:BAAALgADCgQJBAAAAA==.Deyndine:BAAALgAECgUJDQAAAA==.',
Dh='Dhurza:BAAALgAFFAIJAgAAAA==.',
Di='Disdain:BAAALgAECgYJDAAAAA==.Div:BAABLgAECn8xAAIcAAkJTB68AADbAgAcAAkJTB68AADbAgAAAA==.',
Do='Dogdays:BAAALgADCgkJCQAAAA==.Doki:BAAALgAECgIJAgAAAA==.Dorden:BAABLgAECn8sAAMDAAgJvQ7yEwBjAQADAAgJvQ7yEwBjAQAfAAcJGBAkDwANAQAAAA==.Dorilax:BAABLgAECn8UAAMgAAgJqxE+IQDZAQAgAAgJqxE+IQDZAQAhAAEJvwFbXgAlAAAAAA==.Dottarus:BAAALgAECgQJBQAAAA==.',
Dr='Draevus:BAAALgAECgQJBQAAAA==.Dragooniar:BAAALgAECgYJEgAAAA==.Draizen:BAAALgAECgkJBgAAAA==.Dralara:BAAALgADCggJDgAAAA==.Dreàd:BAABLgAECn8XAAIZAAYJCBMMHgAnAQAZAAYJCBMMHgAnAQAAAA==.Driadora:BAAALgAECgIJAgAAAA==.Drinna:BAAALgAECgMJBgAAAA==.Drizzette:BAAALgADCgEJAQAAAA==.Droataxh:BAAALgADCgMJAwABLgAECgkJMQAEAOAgAA==.Droataxm:BAABLgAECn8xAAIEAAkJ4CAVAwAbAwAEAAkJ4CAVAwAbAwAAAA==.Druntress:BAABLgAECn8VAAIJAAgJ0xIyLQDDAQAJAAgJ0xIyLQDDAQAAAA==.',
Du='Duarraag:BAAALgADCgIJAQAAAA==.',
['Dà']='Dàvid:BAAALgAFFAEJAQAAAA==.Dàvìd:BAAALgAECgQJBAAAAA==.',
['Dè']='Dèmonic:BAAALgADCgIJAgAAAA==.',
['Dë']='Dëërez:BAAALgAECgYJDgAAAA==.',
Eb='Eburi:BAABLgAECn8WAAIBAAgJ8hUbHADfAQABAAgJ8hUbHADfAQAAAA==.',
Ed='Edgybear:BAAALgADCggJCAAAAA==.',
Ei='Eililis:BAAALgAECgMJBAAAAA==.',
El='Elani:BAAALgAECgMJAwABLgAECgYJDwAHAAAAAA==.Elaynaa:BAAALgAECgQJBwAAAA==.Eledweth:BAAALgADCgEJAgAAAA==.Elemengoat:BAAALgADCgQJBAAAAA==.Elfstar:BAAALgAECgMJBAAAAA==.Elihe:BAAALgADCgEJAQAAAA==.Elishaunt:BAAALgAECgUJDAAAAA==.Elivan:BAAALgAECgYJBgAAAA==.Elleth:BAAALgAECgYJDQAAAA==.Eloper:BAAALgAFFAEJAwABLgAECgEJAQAHAAAAAA==.Elvoidra:BAAALgAECgIJAgAAAA==.Elykk:BAAALgAECgYJCAAAAA==.',
Em='Emberana:BAAALgADCgUJBQAAAA==.',
En='Endb:BAAALgADCggJFgAAAA==.Enjin:BAAALgADCgUJBQAAAA==.Envi:BAAALgADCgUJBQAAAA==.',
Er='Erisaria:BAAALgADCgQJBQAAAA==.Erixi:BAAALgAECgQJCwAAAA==.Erodoreal:BAAALgAECgcJDgAAAA==.',
Et='Etheria:BAAALgAECgYJCAAAAA==.',
Ev='Evocore:BAAALgAECgYJDAAAAA==.',
Ex='Excelimagust:BAAALgAECgMJBQAAAA==.',
Fa='Faithful:BAAALgAECgcJBwAAAA==.Falanor:BAAALgAECgQJBAABLgAECgYJCQAHAAAAAA==.Falcdhruid:BAAALgAECgIJAgAAAA==.Fangrage:BAAALgAECgMJBAAAAA==.Farundi:BAAALgADCgIJAgAAAA==.Fayemoon:BAAALgAECgUJBgAAAA==.',
Fe='Felara:BAAALgAECgYJBgABLgAECggJFgAiAMsZAA==.Felbutton:BAAALgAECgQJCAAAAA==.Feldemon:BAAALgAECgQJBgAAAA==.Fellost:BAAALgAECgQJBQABLgAECggJFgAiAMsZAA==.Felsen:BAAALgADCgEJAQABLgAECggJFgAiAMsZAA==.Felwit:BAABLgAECn8WAAIiAAgJyxkRDwAYAgAiAAgJyxkRDwAYAgAAAA==.Fennec:BAAALgAECgYJDwAAAA==.',
Fh='Fhyn:BAAALgAECgQJBgAAAA==.',
Fi='Fitzooth:BAAALgAFFAEJAQAAAA==.',
Fl='Flamos:BAAALgADCgYJBgAAAA==.Florabelle:BAAALgADCgkJDAABLgAECgcJEAAHAAAAAA==.Florid:BAAALgAECgYJBwAAAA==.',
Fo='Foshomomo:BAABLgAECn8WAAIjAAYJxxfBEACeAQAjAAYJxxfBEACeAQAAAA==.Fozzle:BAABLgAECn8aAAIEAAgJuwoARABiAQAEAAgJuwoARABiAQAAAA==.',
Fr='Fredoku:BAAALgAECgMJAwAAAA==.Frenndi:BAAALgAECgMJBQAAAA==.Frostbites:BAAALgAECgEJAQAAAA==.',
Fy='Fynedge:BAABLgAECn8UAAIKAAYJLwcPZADqAAAKAAYJLwcPZADqAAAAAA==.Fynnyntyss:BAABLgAECn8jAAIkAAgJag+9AwCmAQAkAAgJag+9AwCmAQAAAA==.Fyrè:BAABLgAECn8iAAISAAgJjiB1CABxAgASAAgJjiB1CABxAgAAAA==.',
['Fâ']='Fârrah:BAAALgAECgIJAgAAAA==.',
Ga='Gabriels:BAAALgADCgcJFQAAAA==.Gabrielspet:BAAALgADCgIJAgAAAA==.Gainsborough:BAAALgADCgcJCgAAAA==.Galactis:BAAALgAECgYJBwAAAA==.Gavinrad:BAAALgAECgQJBAAAAA==.',
Ge='Gelirri:BAAALgADCgIJAgAAAA==.Getschwiftyy:BAAALgADCgIJAQAAAA==.',
Gi='Githnor:BAABLgAECn8jAAIKAAgJ1QcBPABWAQAKAAgJ1QcBPABWAQAAAA==.',
Go='Goretall:BAAALgADCgYJCAAAAA==.Gothen:BAAALgADCgEJAQAAAA==.',
Gr='Graelyn:BAABLgAECn8XAAMKAAcJLAvsjABhAQAKAAcJVgrsjABhAQAcAAIJQQmSQQA3AAAAAA==.Grimseth:BAAALgADCgUJBQAAAA==.Grimwharf:BAAALgAECgQJBgAAAA==.Grum:BAAALgADCgUJBQAAAA==.Grunaelyn:BAAALgAECgcJEgAAAA==.',
Gu='Guerrier:BAAALgAECgYJDQAAAA==.Gustgut:BAAALgAECgEJAQAAAA==.',
Ha='Haelynn:BAAALgADCgcJDAAAAA==.Hahkolhanna:BAAALgADCggJEwAAAA==.Handrido:BAAALgAECgYJCgAAAA==.Hantaro:BAAALgADCgMJAwAAAA==.Hasuna:BAAALgAECgYJCgAAAA==.',
He='Heikuro:BAABLgAECn8YAAMRAAYJxyBLBQCJAQARAAQJqyFLBQCJAQAQAAYJvhnYZgBtAQAAAA==.Heris:BAAALgADCgcJDAAAAA==.',
Hi='Hibby:BAAALgAECgMJBAAAAA==.',
Ho='Holymilk:BAAALgAECgIJAgAAAA==.Holysalt:BAAALgADCgUJCwAAAA==.Honadain:BAAALgAECgUJCAAAAA==.Honordin:BAABLgAECn8pAAIKAAgJOCE5CQCKAgAKAAgJOCE5CQCKAgAAAA==.Hordestalker:BAAALgAECgQJBwAAAA==.Houllian:BAAALgAECgUJCAAAAA==.',
Hu='Hucha:BAAALgADCggJCAAAAA==.Hundren:BAAALgAECgEJAQAAAA==.',
Hw='Hweilan:BAAALgADCgUJBQAAAA==.',
['Hö']='Hölyföx:BAAALgAECgQJBAAAAA==.',
Ia='Iamearl:BAAALgADCgkJFwAAAA==.Iamirishgirl:BAAALgADCgIJAgAAAA==.',
Ic='Icyhotness:BAAALgADCgYJBgAAAA==.Icê:BAAALgADCgcJEgAAAA==.',
Ik='Iklyn:BAAALgAECgMJAQAAAA==.',
Il='Illanna:BAAALgADCgcJCQAAAA==.',
Im='Imckickinit:BAAALgAECgQJBAAAAA==.Imorith:BAAALgAECgYJCQAAAA==.',
In='Inania:BAAALgAECggJEwAAAA==.Inception:BAAALgAECgIJAgAAAA==.Incidental:BAABLgAECn8xAAIIAAkJFyRwAABLAwAIAAkJFyRwAABLAwAAAA==.Inconell:BAABLgAECn8WAAIlAAYJ+wOVNAC5AAAlAAYJ+wOVNAC5AAAAAA==.Invega:BAAALgADCgkJDQAAAA==.',
Ir='Iric:BAAALgAECgEJAgAAAA==.Irinal:BAAALgADCgcJBwAAAA==.Ironi:BAABLgAECn8mAAMUAAgJ4BUVGQC4AQAUAAcJFxUVGQC4AQATAAUJ1QMGbABvAAAAAA==.',
Is='Isai:BAAALgAECgEJAQAAAA==.Iskandar:BAABLgAECn8gAAIlAAgJHBbCDQDXAQAlAAgJHBbCDQDXAQAAAA==.',
Iy='Iyashaau:BAAALgAECgEJAgAAAQ==.',
Iz='Izaer:BAAALgAECgYJEgAAAA==.Iziel:BAAALgAECgUJDQAAAA==.',
Ja='Jababa:BAAALgADCgMJAwAAAA==.Jabzaklok:BAAALgAECgcJEQAAAA==.Jahirah:BAABLgAECn8YAAIEAAcJuhVLOwB9AQAEAAcJuhVLOwB9AQAAAA==.Jaleika:BAAALgADCgcJBwAAAA==.Janaian:BAABLgAECn8aAAMTAAgJhBLkGgAkAQATAAgJhBLkGgAkAQAUAAMJ7g34nACRAAAAAA==.Jarius:BAABLgAECn8WAAIGAAYJbglfJgAWAQAGAAYJbglfJgAWAQAAAA==.Jazaray:BAAALgADCgcJBwAAAA==.',
Je='Jean:BAABLgAECn8kAAISAAgJMB3ACQBgAgASAAgJMB3ACQBgAgAAAA==.Jeez:BAAALgAFFAIJAgAAAA==.Jeri:BAACLgAFFH8QAAMJAAUJxRXZEgAPAQAJAAQJlgfZEgAPAQASAAMJghyJFACxAAAuAAQKfx8AAxIACAlBI9k3AM8BAAkABglVHCwoAOUBABIABwnKH9k3AM8BAAAA.Jeriaze:BAAALgADCgkJEgAAAA==.',
Jo='Jokuo:BAAALgADCgEJAQAAAA==.Jonyy:BAAALgADCgcJCAAAAA==.Joona:BAAALgADCgUJBQAAAA==.Jorianna:BAAALgAECgYJCgAAAA==.Joru:BAACLgAFFH8UAAImAAYJKRxHAAARAgAmAAYJKRxHAAARAgAuAAQKfxcAAiYACAnIJJYDAPMCACYACAnIJJYDAPMCAAAA.',
Jy='Jynxmaze:BAAALgADCgQJAwAAAA==.',
['Jí']='Jím:BAAALgADCgQJBAABLgAECggJFwANAFskAA==.',
Ka='Kaai:BAAALgAECgYJDQAAAA==.Kabaul:BAABLgAECn8pAAMlAAkJTyHIAAAjAwAlAAkJTyHIAAAjAwAeAAEJcRORPgA7AAAAAA==.Kabir:BAABLgAECn8WAAIEAAYJsAohYQAZAQAEAAYJsAohYQAZAQAAAA==.Kadria:BAAALgAECgQJCwAAAA==.Kail:BAAALgAECgUJDwAAAA==.Kailanii:BAABLgAECn8XAAMUAAcJ5xLrHgCJAQAUAAcJ5xLrHgCJAQATAAIJ5QZBdABRAAAAAA==.Kaiscer:BAAALgAECgMJBAAAAA==.Kaitsura:BAAALgADCgUJBQAAAA==.Kaiyne:BAABLgAECn8gAAMNAAgJkBfCIwCiAQANAAgJkBfCIwCiAQAVAAEJdQ8IcQA1AAAAAA==.Kajiere:BAAALgADCgIJAgAAAA==.Kalagon:BAAALgADCgYJBgAAAA==.Kalakeri:BAAALgADCgMJAwAAAA==.Kalaman:BAAALgAECgYJCgAAAA==.Kalian:BAAALgAECgYJEAAAAA==.Kalito:BAAALgAECgQJDQAAAA==.Kamb:BAABLgAECn8XAAIRAAYJwxcGBwBQAQARAAYJwxcGBwBQAQAAAA==.Karalee:BAAALgAECgIJAwAAAA==.Karn:BAAALgADCgEJAQAAAA==.Katieey:BAACLgAFFH8cAAIFAAcJPyUCAAD0AgAFAAcJPyUCAAD0AgAuAAQKfxcAAwUACQnYJMMHAPgCAAUACAmTJMMHAPgCABkABAmiHX87AF8BAAAA.Kayde:BAAALgAECgYJDAAAAA==.Kayil:BAAALgAECgYJBgAAAA==.Kayl:BAABLgAECn8iAAMDAAgJRxLvDgCeAQADAAgJ7hHvDgCeAQAkAAQJPxHQKADZAAAAAA==.Kaylli:BAAALgAECgIJAwAAAA==.',
Ke='Kedalin:BAAALgAECgIJAgAAAA==.Keelnin:BAAALgAECgIJBAAAAA==.Keloko:BAAALgAECgQJBgAAAA==.Kennyloggy:BAACLgAFFH8YAAITAAYJmiPAAABWAgATAAYJmiPAAABWAgAuAAQKfzUAAhMACQlOJjEAAIADABMACQlOJjEAAIADAAAA.Kevris:BAABLgAECn8YAAINAAcJdA46OABMAQANAAcJdA46OABMAQABLgAECgcJGAAEALoVAA==.Keydan:BAAALgAECgQJCAAAAA==.',
Kh='Khaitiff:BAAALgADCgYJBgAAAA==.Khyn:BAAALgAECgQJBAABLgAECgQJBgAHAAAAAA==.',
Ki='Killrok:BAAALgADCgUJBQAAAA==.Kinikey:BAAALgAECgQJBwAAAA==.',
Kl='Klassy:BAABLgAECn8pAAIOAAgJdCMmAwBsAgAOAAgJdCMmAwBsAgAAAA==.',
Ko='Kolosim:BAAALgADCgYJBgAAAA==.Koppi:BAAALgAECgMJBgAAAA==.Korru:BAAALgAECgQJDQAAAA==.Kotie:BAABLgAECn8eAAITAAgJIxNrDQC3AQATAAgJIxNrDQC3AQAAAA==.',
Kr='Kramz:BAAALgAFFAIJAgAAAA==.Kronar:BAAALgAECgMJBgAAAA==.',
Ku='Kumojo:BAAALgADCgYJBgAAAA==.Kunka:BAAALgAECgMJAwAAAA==.Kurgan:BAAALgAECgEJBQAAAA==.',
Ky='Kyojin:BAAALgAECgEJAQAAAA==.Kyoshino:BAAALgAECgMJAwAAAA==.Kyrgune:BAAALgADCgkJDgAAAA==.',
['Kî']='Kîkuko:BAAALgAECgQJBAAAAA==.',
['Kÿ']='Kÿliah:BAAALgAECgEJAQAAAA==.',
La='Lalo:BAAALgAECgIJAgAAAA==.Landilion:BAAALgADCgYJBgAAAA==.Laoftey:BAABLgAECn8kAAMFAAgJ6B5nCABkAgAFAAgJ6B5nCABkAgAZAAEJ2Q9YiQAvAAAAAA==.Laofty:BAAALgADCgYJBgAAAA==.Lar:BAAALgADCgEJAgAAAA==.Laserbeam:BAAALgAECgUJCQABLgAECggJFwANACcgAA==.Lasmori:BAAALgAECgYJDwAAAA==.Lazaris:BAAALgADCgYJBgAAAA==.',
Le='Leglock:BAAALgAECgYJDgAAAA==.Lesbihonest:BAAALgAECgYJEQAAAA==.',
Li='Liendria:BAAALgADCgIJAgAAAA==.Lifensoftpaw:BAACLgAFFH8VAAMPAAYJWxaDAQC9AQAPAAUJjBmDAQC9AQAjAAQJSQHJEQDCAAAuAAQKfyIABA8ACQmSI1kLAMQCAA8ACQmSI1kLAMQCAAgABQl3HKI4AGcBACMAAglwAT9zAB8AAAAA.Lightcaller:BAAALgADCgEJAQAAAA==.Lightflasher:BAAALgAECgcJDwAAAA==.Likkash:BAAALgADCgUJBwABLgAECggJIgAdAHgTAA==.Linthabeela:BAAALgADCgcJDgAAAA==.Lishalthen:BAAALgADCggJCAAAAA==.Lisyanthus:BAAALgAECgEJAQAAAA==.Livicecia:BAAALgAECggJEAAAAA==.',
Lo='Loaftey:BAAALgADCggJCAAAAA==.Longworth:BAAALgADCgIJAgAAAA==.Lookman:BAAALgAECgYJEAAAAA==.Lothema:BAAALgAECgYJCgAAAA==.Lowang:BAAALgAECgEJAQAAAA==.',
Lu='Lucaromu:BAAALgAECgEJAQAAAA==.Lucielinna:BAAALgAECgQJBAABLgAECgYJCAAHAAAAAA==.Luckiiem:BAABLgAECn8gAAIEAAgJoh+PDQB0AgAEAAgJoh+PDQB0AgAAAA==.Luisfriendsn:BAAALgADCgEJAQAAAA==.Lunabreeze:BAAALgADCgcJBwAAAA==.Lunarkin:BAAALgAECgYJDgAAAA==.Luoma:BAAALgAECgUJDQAAAA==.Luthane:BAABLgAECn8TAAIKAAYJJQcdYgDvAAAKAAYJJQcdYgDvAAAAAA==.',
Ly='Lyfeliss:BAAALgAECgYJDAAAAA==.Lynnesa:BAAALgAECgIJAgAAAA==.',
Ma='Maccolyn:BAABLgAECn8YAAIKAAgJKxMnJgCrAQAKAAgJKxMnJgCrAQAAAA==.Magicpie:BAABLgAECn8nAAIgAAgJxh6VEQBVAgAgAAgJxh6VEQBVAgAAAA==.Magikar:BAAALgADCgcJBwAAAA==.Magiren:BAAALgAECgEJAgAAAA==.Mahlock:BAABLgAECn8qAAIMAAgJdhgiBgAYAgAMAAgJdhgiBgAYAgAAAA==.Mainah:BAAALgAECgIJAgAAAA==.Makanai:BAAALgAECgYJDQAAAA==.Makenai:BAAALgADCgcJBwABLgAECgYJDQAHAAAAAA==.Makishi:BAABLgAECn8WAAIRAAYJHyBtBACtAQARAAYJHyBtBACtAQAAAA==.Malferious:BAAALgADCgYJBgAAAA==.Malfura:BAAALgAECgUJBwAAAA==.Malário:BAAALgADCgMJAwAAAA==.Manamontana:BAABLgAECn8XAAIEAAcJaQ4EnACdAQAEAAcJaQ4EnACdAQAAAA==.Maplebunny:BAAALgADCgEJAQAAAA==.Mascdomtop:BAABLgAECn8dAAMgAAgJ/h53CADEAgAgAAgJ/h53CADEAgAnAAgJRAqOFABdAQAAAA==.Maube:BAAALgAECgEJAgABLgAFFAIJCAAcAGwUAA==.Mazzarzul:BAAALgAECgYJEwABLgAECggJEAAHAAAAAA==.',
Me='Meebles:BAABLgAECn8jAAILAAgJ8g7hCQAxAQALAAgJ8g7hCQAxAQAAAA==.Meiana:BAABLgAECn8ZAAIDAAgJBhSVJwCAAQADAAgJBhSVJwCAAQAAAA==.Mekanismz:BAAALgADCgkJCQABLgAECggJJgAlAGokAA==.Melanthia:BAAALgAECgEJAQAAAA==.Melasmus:BAAALgAECgEJAQAAAA==.Mendu:BAAALgADCgcJBwAAAA==.Mes:BAAALgAECgcJEAAAAA==.',
Mi='Micklaa:BAAALgAECgYJEwAAAA==.Mightychi:BAAALgAECgUJDQAAAA==.Milan:BAAALgADCgkJCQAAAA==.Milicka:BAAALgADCgkJBwAAAA==.Milkbunny:BAAALgADCgMJAwAAAA==.Millenium:BAAALgAECgQJCgAAAA==.Mingtai:BAAALgAECgYJDgAAAA==.Mirixa:BAAALgADCgYJBgAAAA==.Mizzakien:BAAALgAECgUJCQAAAA==.',
Mo='Monk:BAACLgAFFH8GAAIIAAMJPBv+GgDEAAAIAAMJPBv+GgDEAAAuAAQKfxsAAggABwkzJQEaADQCAAgABwkzJQEaADQCAAAA.Monkyo:BAAALgAECgcJEgAAAA==.Monrea:BAAALgADCgUJEAABLgAECgUJCAAHAAAAAA==.Moondolli:BAAALgADCgEJAQAAAA==.Moonriver:BAABLgAECn8iAAQFAAcJAQpPWgAfAQAFAAcJAQpPWgAfAQAmAAYJpQnFDAAMAQAZAAMJeAgjOACPAAAAAA==.Moonsinde:BAAALgAECgkJEAAAAA==.Moranta:BAAALgAECgYJEwAAAA==.Moressandra:BAAALgAECgYJDAAAAA==.',
Mu='Muncher:BAAALgAECgEJAQAAAA==.Munchiss:BAAALgADCgEJAQAAAA==.Murathiel:BAAALgAECgQJCQABLgAFFAQJCAAjAKcgAA==.Murdermass:BAAALgADCgkJDQAAAA==.',
My='Myke:BAAALgAECgEJAQAAAA==.Mykellcat:BAAALgAECgQJDAAAAA==.Mysticarc:BAAALgAECggJEgAAAA==.Mysticmurv:BAABLgAECn8ZAAIoAAgJLxy6EABcAgAoAAgJLxy6EABcAgAAAA==.Myvirdaeth:BAAALgADCgEJAQAAAA==.',
Na='Naeni:BAAALgAECgEJAQAAAA==.Nahli:BAAALgAECgkJDwAAAA==.Nakkarn:BAAALgADCgQJBAAAAA==.Nalynahwe:BAAALgAECgYJDgAAAA==.Narima:BAAALgAECgUJDQAAAA==.Naura:BAAALgADCgEJAQAAAA==.Navirose:BAAALgAECgQJBAAAAA==.',
Ne='Neltheron:BAAALgADCgIJAgAAAA==.',
Nh='Nhala:BAAALgAECgIJAgABLgAECgQJBQAHAAAAAA==.',
Ni='Nightestrike:BAAALgADCgQJBAAAAA==.Nikodem:BAAALgAECgYJEwAAAA==.Ninali:BAAALgAECgYJBAAAAA==.Ninerva:BAAALgAECgkJBwAAAA==.',
No='Nore:BAABLgAECn8WAAIhAAYJ8RrpCwDLAQAhAAYJ8RrpCwDLAQAAAA==.',
Ny='Nyali:BAAALgAECgEJAQABLgAECgcJFwAUAOcSAA==.',
['Nà']='Nàdya:BAABLgAECn8nAAIFAAgJRiGDCADtAgAFAAgJRiGDCADtAgAAAA==.',
['Nî']='Nîkodemus:BAAALgADCgYJBgAAAA==.',
Ob='Oblivions:BAABLgAECn8mAAMlAAgJaiTwCQAQAwAlAAgJaiTwCQAQAwAeAAQJix6ECQBrAQAAAA==.Oblivionsdk:BAAALgAECgEJAQABLgAECggJJgAlAGokAA==.',
Od='Odyfan:BAAALgADCgEJAQAAAA==.',
Of='Ofelia:BAAALgAECgYJDAAAAA==.',
Og='Ogion:BAAALgAECgEJAQAAAA==.',
Om='Omniray:BAABLgAECn8WAAITAAYJhhHOGQAuAQATAAYJhhHOGQAuAQAAAA==.Omnitruce:BAAALgAECgMJAwAAAA==.',
On='Onekark:BAAALgAECgQJCAABLgAECgYJBgAHAAAAAA==.Onirei:BAAALgADCgEJAwAAAA==.',
Op='Ophèlia:BAAALgADCgIJBwAAAA==.',
Or='Orckus:BAAALgAECgMJBgAAAA==.Oreosbunny:BAAALgAECgEJAQAAAA==.',
Os='Osvaldr:BAAALgAECgQJBQAAAA==.',
Ow='Owil:BAAALgAECggJEgAAAA==.',
Pa='Pandaburn:BAAALgAECgYJEQAAAA==.Pandais:BAAALgAECgYJCwAAAA==.Paranne:BAABLgAECn8jAAIEAAgJ8hp1GAAaAgAEAAgJ8hp1GAAaAgAAAA==.Paroxism:BAABLgAECn8dAAITAAgJjyKiAgC8AgATAAgJjyKiAgC8AgAAAA==.Parthurnax:BAAALgAECgUJCgAAAA==.Patapouf:BAABLgAECn8WAAIhAAYJACOXBQBdAgAhAAYJACOXBQBdAgAAAA==.Patrisse:BAAALgADCgMJAwAAAA==.Pauhana:BAAALgADCgkJDwABLgAECgUJDQAHAAAAAA==.',
Pe='Peanût:BAABLgAECn8kAAIUAAgJDBVPFADkAQAUAAgJDBVPFADkAQAAAA==.Pesante:BAABLgAECn8hAAIhAAcJBBz0CAAEAgAhAAcJBBz0CAAEAgAAAA==.',
Ph='Phaket:BAAALgADCgYJBwAAAA==.Phatums:BAACLgAFFH8IAAIBAAMJriJcKgAUAQABAAMJriJcKgAUAQAuAAQKfyEAAgEACAnjIoASAA0DAAEACAnjIoASAA0DAAAA.Philippy:BAAALgADCgYJBwAAAA==.',
Pi='Pika:BAAALgAECgcJEwAAAA==.Pinix:BAAALgADCgYJCgAAAA==.Pinulito:BAAALgADCgMJAwAAAA==.Pippá:BAAALgAECgQJBAAAAA==.',
Po='Polonius:BAAALgAECgYJDQAAAA==.',
Pr='Praline:BAAALgADCgEJAQAAAA==.Pranaverde:BAAALgAECgYJDAAAAA==.Prisevide:BAAALgAECgYJEgAAAA==.Priss:BAAALgADCgcJDgAAAA==.',
Ps='Psyched:BAAALgADCgEJAQAAAA==.',
Pu='Pumpy:BAAALgADCgcJCAAAAA==.',
Py='Pythe:BAABLgAECn8jAAIKAAgJ3R5iDwBEAgAKAAgJ3R5iDwBEAgAAAA==.',
Qa='Qap:BAAALgAECgcJEgAAAA==.Qara:BAAALgADCgYJBgAAAA==.',
Qu='Qualnorr:BAAALgAECgUJBgAAAA==.Queldraayan:BAAALgAECgIJBAAAAA==.Quixediah:BAACLgAFFH8FAAIUAAMJOxXAFQDpAAAUAAMJOxXAFQDpAAAuAAQKfx0AAhQACAn0IZYJAPkCABQACAn0IZYJAPkCAAAA.Quixhea:BAAALgAECgUJDAABLgAFFAMJBQAUADsVAA==.Quixxum:BAAALgADCgMJAwABLgAFFAMJBQAUADsVAA==.',
Ra='Radalas:BAAALgAECgYJDgAAAA==.Radreliris:BAAALgAECgQJBQAAAA==.Rahdalas:BAAALgADCgEJAQABLgAECgYJDgAHAAAAAA==.Rally:BAAALgAECgYJDQAAAA==.Ramanujan:BAAALgAECgIJAgAAAA==.Ramcco:BAEALgAECgYJCwAAAA==.Ranelle:BAABLgAECn8jAAIgAAgJ4BDREACcAQAgAAgJ4BDREACcAQAAAA==.Rasmira:BAAALgAECgYJEAAAAA==.Ravenis:BAABLgAECn8bAAIMAAgJch9BAgCjAgAMAAgJch9BAgCjAgAAAA==.Razekial:BAAALgAECgYJCQAAAA==.Razelikh:BAAALgADCgYJBgAAAA==.',
Re='Reedem:BAABLgAECn8UAAIPAAYJdwo/JQDFAAAPAAYJdwo/JQDFAAAAAA==.Regilock:BAACLgAFFH8TAAQNAAcJEhsiAgAVAgANAAYJtBoiAgAVAgAVAAQJjxH9AQApAQAWAAEJUwwlBgBTAAAuAAQKfyEABA0ACQleJdIIADoDAA0ACAkpJdIIADoDABUABAnsHhIiAEUBABYAAQkAAO4jAGIAAAAA.Regilocklr:BAAALgAECgYJDwAAAA==.Reikí:BAABLgAECn8cAAIEAAgJfBHSLQCsAQAEAAgJfBHSLQCsAQAAAA==.Relarria:BAAALgADCgMJAwAAAA==.Renbe:BAAALgADCgYJCAAAAA==.Renwald:BAABLgAECn8UAAMKAAYJdhF5kwBWAQAKAAYJdhF5kwBWAQAcAAMJzQo2NAB3AAAAAA==.Revgard:BAAALgAECgYJDQAAAA==.',
Rh='Rhasalgul:BAAALgAECgMJBAAAAA==.',
Ro='Rolhen:BAAALgAECgUJBgAAAA==.Ronso:BAAALgADCgQJBAAAAA==.Ronta:BAAALgADCgYJCgAAAA==.Rowain:BAAALgADCgcJBwAAAA==.',
Ru='Rustyheals:BAAALgADCgcJBwAAAA==.',
Ry='Ryanari:BAAALgAECgQJBQAAAA==.Rylacus:BAAALgAECgQJCwAAAA==.',
['Rê']='Rêgret:BAAALgADCgYJCQAAAA==.',
Sa='Saanda:BAAALgAECgUJCAAAAA==.Sagazboy:BAAALgAECgYJDwABLgAECggJHgAKAH4QAA==.Sagazpally:BAABLgAECn8eAAIKAAgJfhDJKwCTAQAKAAgJfhDJKwCTAQAAAA==.Salandre:BAAALgADCgMJAwAAAA==.Salutations:BAAALgAFFAEJAQAAAA==.Salv:BAAALgADCgIJAgAAAA==.Sandp:BAAALgAFFAEJAQAAAA==.Sapphin:BAAALgADCgQJBAAAAA==.Sarlef:BAAALgAECgUJEgAAAA==.Sashafel:BAAALgADCggJCAAAAA==.',
Sc='Scarm:BAAALgADCgUJCgAAAA==.Scyithe:BAAALgADCgEJAQAAAA==.',
Se='Sellidra:BAAALgAECgYJDgAAAA==.Sendcatpics:BAABLgAECn8sAAMGAAkJPRBfDwDrAQAGAAkJPRBfDwDrAQAKAAUJBBrugwByAQABLgAFFAEJAQAHAAAAAA==.Seo:BAAALgAFFAIJBAAAAA==.Serenitara:BAAALgADCgYJBgAAAA==.Sethia:BAAALgADCgQJBAABLgADCgUJBQAHAAAAAA==.Sevotarthe:BAAALgADCgMJAwAAAA==.Seyana:BAAALgAECgYJDwAAAA==.',
Sh='Shadowkaos:BAAALgAECgUJCAAAAA==.Shaffer:BAAALgAECgcJDQAAAA==.Shellmage:BAAALgAECgYJCwAAAA==.Shellshocker:BAACLgAFFH8HAAIZAAMJPSD3CwAtAQAZAAMJPSD3CwAtAQAuAAQKfxYAAhkACAnnJfYIAAMDABkACAnnJfYIAAMDAAAA.Shermantånk:BAAALgADCgYJDwAAAA==.Sheydon:BAAALgADCgQJBAAAAA==.Shiftstain:BAAALgADCgIJAgAAAA==.Shikï:BAABLgAECn8gAAInAAgJ4SEADgCjAgAnAAgJ4SEADgCjAgAAAA==.Shivermoón:BAABLgAECn8gAAIUAAgJrBIoFgDSAQAUAAgJrBIoFgDSAQAAAA==.Shobek:BAAALgAECgYJBgAAAA==.Shortie:BAAALgADCgYJBgAAAA==.',
Si='Sigesar:BAABLgAECn8XAAIgAAYJzAa+IgDqAAAgAAYJzAa+IgDqAAAAAA==.Silvaria:BAAALgAECgMJBAAAAA==.Simina:BAAALgAECgEJAQAAAA==.Simpforsouls:BAAALgAECgYJBgAAAA==.Simura:BAAALgAFFAEJAQAAAA==.Sinamara:BAAALgADCgkJFwAAAA==.Sinsimella:BAAALgADCgYJCAAAAA==.Sinõn:BAAALgAECgQJBQAAAA==.',
Sk='Skyliner:BAAALgAECgQJBQAAAA==.Skyskitty:BAAALgAECgYJCwAAAA==.Skywatcher:BAABLgAECn8WAAISAAYJIAnZQwAIAQASAAYJIAnZQwAIAQAAAA==.',
Sl='Slaughtering:BAAALgAECgYJDQAAAA==.',
Sm='Smesus:BAAALgAECgEJAQAAAA==.Smitemare:BAAALgAECgMJAwAAAA==.',
So='Solare:BAAALgADCgYJDgAAAA==.Solianti:BAAALgADCgYJBgAAAA==.Solodan:BAAALgAECgYJDQAAAA==.Solodane:BAAALgAECgYJBgAAAA==.Sonnwar:BAABLgAECn8hAAIGAAgJiBtbEgDIAQAGAAgJiBtbEgDIAQAAAA==.',
Sp='Spliphtoker:BAAALgAECgQJBQAAAA==.Spookytotems:BAABLgAECn8fAAImAAcJyxXdBgCWAQAmAAcJyxXdBgCWAQAAAA==.',
St='Stenston:BAAALgAECgYJCwAAAA==.Sterede:BAAALgAECgIJAgAAAA==.Stonehenge:BAAALgAECgYJDgAAAA==.Stormb:BAAALgADCgkJFQAAAA==.Stormwolves:BAAALgAECgIJAgAAAA==.',
Sy='Sylphr:BAAALgAECgQJCQAAAA==.Sylphwild:BAAALgAECgIJAgABLgAECgQJBgAHAAAAAA==.Sylvanase:BAAALgAECgcJCgAAAA==.Synapze:BAABLgAECn8WAAIEAAYJVg6oVgAxAQAEAAYJVg6oVgAxAQAAAA==.Syreite:BAABLgAECn8cAAILAAgJMBQ5BgCaAQALAAgJMBQ5BgCaAQAAAA==.Syreyna:BAAALgADCgIJAgAAAA==.',
Ta='Taessa:BAAALgADCggJBAAAAA==.Tahwye:BAAALgADCgYJFwAAAA==.Tainipuni:BAAALgAECgUJDAAAAA==.Takemi:BAAALgAECggJCAAAAA==.Tallac:BAAALgADCgYJBgABLgAECggJKgAcAMIYAA==.Tallaric:BAAALgADCgkJFAABLgAECggJKgAcAMIYAA==.Tallic:BAABLgAECn8qAAIcAAgJwhi9BwCcAQAcAAgJwhi9BwCcAQAAAA==.Tamarah:BAAALgAECgYJCgAAAA==.Tamzyyn:BAAALgAECgYJCgAAAA==.Tandemonium:BAAALgAECgEJAQABLgAFFAQJCgAoAO8gAA==.Taniz:BAABLgAECn8VAAMSAAgJPBoNGQByAgASAAgJLBoNGQByAgAJAAMJ9Q2adgBkAAAAAA==.Tankfu:BAAALgAECgUJBgAAAA==.Tarsi:BAAALgAECgQJCQAAAA==.Tashoonne:BAAALgADCgUJBwAAAA==.Taylin:BAAALgADCgMJAwABLgAECgQJBgAHAAAAAA==.',
Te='Teareagana:BAAALgAECgYJCgAAAA==.Tearinurside:BAAALgAECgYJDQAAAA==.Teddy:BAAALgADCgUJBQABLgAECggJHwAjAIYfAA==.Telchar:BAAALgAECgUJCQAAAA==.Telidrel:BAAALgADCgMJAwAAAA==.Teratin:BAABLgAECn8YAAIIAAcJ2iL9BgApAgAIAAcJ2iL9BgApAgAAAA==.Tevellan:BAAALgADCgYJBwAAAA==.',
Th='Thaddeaus:BAABLgAECn8XAAIiAAgJDBkaDQA6AgAiAAgJDBkaDQA6AgAAAA==.Thaddeus:BAABLgAECn8XAAIKAAYJHBokLQCNAQAKAAYJHBokLQCNAQAAAA==.Thauris:BAAALgAECgEJAQAAAA==.Thealin:BAAALgAECgMJAwAAAA==.Thebeefyone:BAAALgAECgYJCwAAAA==.Thelesar:BAAALgADCgYJCAAAAA==.Therizin:BAAALgAECgYJDAAAAA==.Thesummoner:BAABLgAECn8XAAMNAAgJJyDVEwDeAgANAAgJJyDVEwDeAgAVAAEJxxVWawA8AAAAAA==.Thicciana:BAAALgAFFAIJAgAAAA==.Thorizan:BAAALgAECgQJBwAAAA==.Thugnificent:BAAALgADCgcJBwAAAA==.Thumpette:BAAALgADCgMJAwAAAA==.Thuviel:BAAALgAECgIJAwAAAA==.Thè:BAAALgAECgYJCwAAAA==.',
Ti='Tierant:BAAALgAECgEJAQAAAA==.Tituz:BAAALgADCgMJBAAAAA==.Tizaria:BAAALgAECgYJDwAAAA==.',
Tm='Tmai:BAAALgAECgYJDQAAAA==.',
To='Tolken:BAAALgAECgEJAQAAAA==.Tominaetor:BAABLgAECn8WAAINAAYJcQl7UwD2AAANAAYJcQl7UwD2AAAAAA==.Tosoto:BAABLgAECn8bAAMlAAgJEhsUBgBUAgAlAAgJEhsUBgBUAgAeAAYJJwxEGAA3AQAAAA==.Toxerus:BAAALgAECgMJBAAAAA==.',
Tr='Trixigossa:BAAALgADCggJEgABLgAECgUJBgAHAAAAAA==.Trobbio:BAAALgADCgIJAgAAAA==.',
Ts='Tso:BAABLgAECn8XAAMjAAcJdRWEFQBjAQAjAAYJ3BaEFQBjAQAPAAEJLQYtUQArAAAAAA==.Tsukuyomï:BAAALgAECgIJBAABLgAECggJIAAnAOEhAA==.',
Tu='Tuskmunkey:BAAALgAECgMJBgAAAA==.',
Ty='Tyernan:BAABLgAECn8iAAMGAAgJQQTnIAA/AQAGAAgJQQTnIAA/AQAKAAIJyAQvJwFRAAAAAA==.Tym:BAAALgADCgkJDAAAAA==.Tyrael:BAABLgAECn8mAAIKAAYJ5AyfZwDhAAAKAAYJ5AyfZwDhAAAAAA==.Tyreanna:BAAALgADCgEJAgAAAA==.Tyrioz:BAABLgAECn8YAAMGAAcJXQ8CIABHAQAGAAcJXQ8CIABHAQAKAAIJ5REoFAFvAAAAAA==.',
Tz='Tzavcat:BAAALgAECgUJEQAAAA==.',
Ul='Uluhn:BAAALgADCggJDgABLgAECgQJBQAHAAAAAA==.',
Ur='Urklesnurkle:BAAALgAECgEJBAAAAA==.',
Uv='Uvsol:BAAALgAECgUJBwAAAA==.',
Va='Vadailla:BAAALgADCgYJDgABLgAECgUJDQAHAAAAAA==.Vahrik:BAAALgAECgEJAQAAAA==.Valcane:BAAALgADCgkJEgAAAA==.Valdictorian:BAAALgAECgEJAQAAAA==.Valius:BAABLgAECn8UAAIkAAYJhxwQAwDDAQAkAAYJhxwQAwDDAQAAAA==.Vallarium:BAAALgADCgUJEQAAAA==.Valornor:BAAALgAECgQJBgAAAA==.Valyerian:BAAALgAECgUJBgAAAA==.Vanacarde:BAAALgAECgUJBQAAAA==.Vandilious:BAAALgAECgYJCQAAAA==.Vandill:BAAALgAECgUJDQABLgAECgYJCQAHAAAAAA==.Vaneadra:BAAALgADCgUJCwAAAA==.',
Ve='Veasnacool:BAAALgAECggJEQAAAA==.Velanlan:BAAALgADCgUJBQAAAA==.Velion:BAAALgADCgYJBgAAAA==.',
Vh='Vhesper:BAAALgAECgMJAwAAAA==.',
Vi='Vii:BAAALgAECgcJDgAAAA==.',
Vo='Voidfisting:BAABLgAECn8lAAMjAAgJ8wf8HgAIAQAjAAgJ8wf8HgAIAQAPAAIJMQe0OABdAAAAAA==.Volfurion:BAAALgADCgQJBAAAAA==.Vontote:BAAALgAECgYJDAAAAA==.Vorix:BAAALgAECgYJDQAAAA==.Vorrel:BAAALgADCgkJFwABLgAECggJIgADAEcSAA==.',
Vu='Vunak:BAAALgADCgcJDQAAAA==.',
['Ví']='Víc:BAAALgAECgYJEgAAAA==.',
Wa='Wandorf:BAEBLgAECn8XAAIBAAYJgwzzTAAZAQABAAYJgwzzTAAZAQAAAA==.Warbacon:BAAALgADCgMJAwAAAA==.Wargyle:BAABLgAECn8YAAMNAAcJCBDnLQB0AQANAAcJCBDnLQB0AQAVAAEJAADDcAA1AAAAAA==.Warwolfe:BAABLgAECn8kAAMNAAgJGAemOQBHAQANAAgJuQamOQBHAQAWAAQJ+QfxFgDIAAAAAA==.Wayler:BAAALgAECgIJAgAAAA==.',
We='Wealthywolf:BAABLgAECn8WAAMOAAcJwwcnFgASAQAOAAcJwwcnFgASAQAJAAEJwgBgmwATAAAAAA==.Werepinguin:BAAALgADCgMJAwAAAA==.',
Wi='Wilbrew:BAAALgADCgUJCgABLgAECggJEgAHAAAAAA==.Wistful:BAAALgAECgIJAgAAAA==.',
Wl='Wlitia:BAAALgAECgMJAwAAAA==.',
Wo='Wolferunner:BAAALgAECgYJDgAAAA==.',
Wr='Wrathome:BAABLgAECn8cAAMNAAcJgxqvQAALAgANAAcJgxqvQAALAgAVAAMJtgrNRgCbAAAAAA==.Wráth:BAAALgADCggJCAAAAA==.',
Xa='Xalatäth:BAAALgAECgMJBAAAAA==.Xaldora:BAAALgADCgcJFgAAAA==.Xandrake:BAAALgAECgYJDAABLgAFFAUJDQADAFMdAA==.',
Xd='Xdxvuu:BAAALgAECgYJDgAAAA==.',
Xe='Xerimok:BAAALgAECgQJCwAAAA==.',
Xi='Xinya:BAAALgAECgYJBwAAAA==.Xipa:BAABLgAECn8fAAIJAAgJxxu7AwDkAQAJAAgJxxu7AwDkAQAAAA==.',
Xl='Xladykahlron:BAAALgADCgYJCAAAAA==.',
Xo='Xolara:BAAALgAECgIJBAAAAA==.',
Xs='Xsavior:BAAALgAECgQJBAAAAA==.Xshan:BAAALgAECgEJAgAAAA==.Xshando:BAAALgAECgQJCwAAAA==.',
Xy='Xyi:BAAALgAECggJEQAAAA==.',
Xz='Xzephyr:BAABLgAECn8jAAITAAgJ0x/GBABpAgATAAgJ0x/GBABpAgAAAA==.',
Ya='Yamato:BAABLgAECn8WAAIiAAgJzgXEEgD9AAAiAAgJzgXEEgD9AAAAAA==.',
Ye='Yesmín:BAAALgAECgMJBAAAAA==.',
Yo='Youwas:BAAALgAECgcJCgAAAA==.Yoveladari:BAAALgADCgIJAgAAAA==.',
Yu='Yukimenoko:BAAALgAECgUJDAAAAA==.Yukmouf:BAABLgAECn8VAAIKAAgJ2BtmIwCbAgAKAAgJ2BtmIwCbAgAAAA==.',
Za='Zabrak:BAAALgAECgIJAgAAAA==.Zakaris:BAAALgADCgIJAgAAAA==.Zalaeran:BAAALgADCgEJAQAAAA==.Zalatath:BAAALgADCgkJHgAAAA==.Zarrov:BAAALgADCgkJGgAAAA==.Zarrove:BAABLgAECn8nAAIPAAgJ0SCJBABiAgAPAAgJ0SCJBABiAgAAAA==.',
Ze='Zea:BAAALgAECgMJBAAAAA==.Zedael:BAABLgAECn8YAAIdAAcJKxjUCgBkAQAdAAcJKxjUCgBkAQAAAA==.Zeltri:BAAALgAECgIJBAAAAA==.Zeritha:BAAALgAECgEJAgAAAA==.',
Zh='Zhatva:BAAALgAECgcJEwAAAA==.Zhöe:BAAALgAECggJEwAAAA==.',
Zo='Zoldor:BAABLgAECn8VAAMNAAYJTRF5PAA9AQANAAUJTRF5PAA9AQAVAAEJAABLdwAtAAAAAA==.Zoleia:BAAALgADCgIJAgAAAA==.Zoral:BAAALgADCgUJBQAAAA==.',
Zu='Zuldokah:BAAALgADCgEJAQAAAA==.',
Zy='Zy:BAAALgADCgkJFAAAAA==.Zycorr:BAAALgAECgMJAwAAAA==.Zyheal:BAAALgAECggJEgAAAA==.Zymor:BAAALgAECgMJBgAAAA==.Zytrex:BAAALgAECgYJBgAAAA==.',
['Äm']='Ämaterasu:BAAALgADCgcJCgABLgAECggJIAAnAOEhAA==.',
['Ða']='Ðaniel:BAAALgAECgYJDQAAAA==.',
['Ðr']='Ðraevus:BAAALgAECgQJDAAAAA==.',
['Ñÿ']='Ñÿx:BAAALgAECgUJDwAAAA==.',
['ßl']='ßlueshield:BAAALgAECgYJEgAAAA==.',
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
