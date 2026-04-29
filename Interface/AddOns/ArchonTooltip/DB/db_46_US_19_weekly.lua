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

local lookup = {'DeathKnight-Unholy','DeathKnight-Frost','Mage-Frost','Shaman-Restoration','Paladin-Holy','Unknown-Unknown','Monk-Brewmaster','Hunter-Marksmanship','Paladin-Retribution','Warlock-Demonology','Hunter-Survival','Monk-Windwalker','Hunter-BeastMastery','Mage-Fire','Mage-Arcane','Rogue-Outlaw','DemonHunter-Devourer','DemonHunter-Vengeance','DeathKnight-Blood','Shaman-Elemental','Paladin-Protection','Evoker-Augmentation','Evoker-Preservation','Warrior-Protection','Evoker-Devastation','Druid-Restoration','Druid-Balance','Warrior-Fury','Shaman-Enhancement','Warrior-Arms','Warlock-Destruction','Monk-Mistweaver','Priest-Holy','Rogue-Subtlety','Druid-Guardian','DemonHunter-Havoc','Priest-Discipline','Warlock-Affliction','Priest-Shadow',}
local provider = {region='US',realm='ArgentDawn',name='US',type='weekly',zone=46,date='2026-04-24',data={Ad='Adaine:BAAALgADCgUJBQAAAA==.Adriana:BAAALgAECgUJCgAAAA==.Adru:BAAALgAECgQJCAAAAA==.',
Ae='Aeglos:BAABLgAECn8cAAMBAAgJCiK8FgDzAgABAAgJCiK8FgDzAgACAAQJ2x9SCQBGAQAAAA==.Aelera:BAAALgADCgkJDgAAAA==.Aentharion:BAAALgAECgYJEQAAAA==.Aer:BAAALgADCgUJBQAAAA==.Aertimis:BAAALgADCgMJAwAAAA==.Aevielyn:BAAALgADCgQJCAAAAA==.',
Ag='Aguth:BAAALgADCgMJAwAAAA==.',
Ai='Aileen:BAAALgAECgcJEAAAAA==.Airiya:BAAALgAECgUJBAAAAA==.',
Aj='Ajami:BAAALgADCgIJAgAAAA==.',
Al='Alacite:BAAALgAECgcJEwAAAA==.Alisonia:BAAALgADCgcJDgAAAA==.Alitikar:BAAALgADCgIJAgAAAA==.Allamura:BAAALgADCgkJBwAAAA==.Alleximage:BAABLgAECn8XAAIDAAgJEhc+UwA+AgADAAgJEhc+UwA+AgAAAA==.Alorren:BAABLgAECn8VAAIEAAYJSgucEgAhAQAEAAYJSgucEgAhAQAAAA==.Althea:BAAALgADCgQJBAAAAA==.Alynia:BAAALgADCgQJBAAAAA==.Alyssa:BAAALgAECgUJBQAAAA==.',
Am='Amodegas:BAABLgAECn8VAAIFAAgJMyBjCADoAgAFAAgJMyBjCADoAgAAAA==.Amonk:BAAALgAECgQJBwAAAA==.Amonra:BAAALgAECgMJAwAAAA==.Amordil:BAAALgADCgQJBAAAAA==.Amynrar:BAAALgADCgcJDQAAAA==.',
An='Ancalagrond:BAAALgADCgUJBQAAAA==.Andrâste:BAAALgADCgEJAQAAAA==.Anecia:BAAALgADCgkJDwABLgAECgQJCAAGAAAAAA==.Animos:BAAALgADCgYJBgAAAA==.Annehathaway:BAAALgAECgEJAQAAAA==.Anothercaion:BAAALgAECgUJDQAAAA==.Anthor:BAAALgADCgMJAwAAAA==.Antiihr:BAACLgAFFH8VAAIHAAYJtyNVAAB6AgAHAAYJtyNVAAB6AgAuAAQKfzEAAgcACQn3JN8AAL4DAAcACQn3JN8AAL4DAAAA.',
Ap='Apix:BAAALgAECgEJAQABLgAECggJFwAIAOoYAA==.',
Ar='Arcaisme:BAAALgAECgUJDQAAAA==.Arcticsnow:BAAALgAECgQJCAAAAA==.Arkose:BAAALgAECgUJBgAAAA==.Arkädia:BAAALgADCgkJDgAAAA==.Armistice:BAABLgAECn8VAAIJAAgJ7CA7EwD5AgAJAAgJ7CA7EwD5AgAAAA==.Artanos:BAAALgAECgEJAQAAAA==.Artiazana:BAAALgADCgEJAgAAAA==.',
As='Ashlyngrace:BAAALgAECgIJAgABLgAECggJHAAEAKMfAA==.Ashlynne:BAABLgAECn8cAAIEAAgJox/YCQDbAgAEAAgJox/YCQDbAgAAAA==.Ashvara:BAAALgADCgcJEgAAAA==.Asora:BAAALgAECgQJCAAAAA==.Aspect:BAAALgAECgEJAgAAAA==.Aspensong:BAAALgAECgYJEQAAAA==.Astracious:BAAALgADCggJEgAAAA==.',
At='Atax:BAAALgAECgYJEQAAAA==.Athená:BAAALgAECgYJBgAAAA==.Atheum:BAAALgADCgQJBAAAAA==.',
Au='Auralyn:BAAALgADCgcJCwAAAA==.',
Av='Avicena:BAAALgAECgUJCAAAAA==.Avicii:BAAALgADCgUJCgAAAA==.Avrice:BAAALgAECgEJAQAAAA==.',
Ax='Axfrosty:BAAALgADCgQJBAAAAA==.Axiona:BAAALgADCgIJBwAAAA==.',
Ay='Ayakia:BAAALgAECgYJBgAAAA==.Ayaku:BAAALgAECgIJAgAAAA==.',
Az='Azuraa:BAAALgADCgUJCAAAAA==.',
Ba='Badshot:BAAALgAECgYJDwAAAA==.Baiogg:BAABLgAECn8YAAIKAAcJLwUTIwAPAQAKAAcJLwUTIwAPAQAAAA==.Baldord:BAAALgADCgMJBAAAAA==.Balthromaww:BAAALgAECgYJBwAAAA==.Balung:BAAALgAECgEJAQAAAA==.Bambu:BAAALgAECgQJBAAAAA==.Bamevoker:BAAALgADCgcJDwABLgAECgQJBAAGAAAAAA==.Bariggs:BAABLgAECn8UAAILAAcJryTDBADGAgALAAcJryTDBADGAgAAAA==.',
Be='Bearlyalive:BAAALgADCgMJAwAAAA==.Beladra:BAAALgADCgUJCwAAAA==.Belekor:BAAALgAECgYJCQAAAA==.Beltayn:BAAALgAECgYJCwAAAA==.Ben:BAABLgAECn8ZAAIMAAgJWRckFABNAgAMAAgJWRckFABNAgAAAA==.Beriadan:BAAALgAECgIJAgAAAA==.Bevee:BAAALgAECgMJBgAAAA==.Bewitchin:BAAALgAECgEJAQAAAA==.',
Bi='Bigponch:BAAALgADCgEJAQAAAA==.Birst:BAAALgADCggJBAAAAA==.Bisque:BAAALgADCgIJAgAAAA==.',
Bl='Bladesrus:BAAALgAECgIJBAAAAA==.Bleddwen:BAAALgAECgMJBAAAAQ==.Bliggix:BAAALgADCgQJBAAAAA==.Blrsama:BAAALgADCgUJBgAAAA==.',
Bo='Bodok:BAAALgAECgYJEAAAAA==.Bohrnir:BAABLgAECn8bAAIEAAcJjR0YCwCLAQAEAAcJjR0YCwCLAQAAAA==.Bokatan:BAAALgAECgEJAQABLgAECggJHAAEAKMfAA==.Boomonster:BAAALgADCgEJAQAAAA==.Boüh:BAAALgAECgQJBQAAAA==.',
Br='Brackiss:BAAALgADCgIJAgAAAA==.Brokiinn:BAACLgAFFH8FAAINAAIJ9BFaFQCvAAANAAIJ9BFaFQCvAAAuAAQKfxoAAg0ACAl1GfYbAF8CAA0ACAl1GfYbAF8CAAAA.Brutalix:BAAALgADCgYJDQAAAA==.Brynda:BAAALgADCgQJBAAAAA==.',
Bu='Budikah:BAAALgAECgQJAgAAAA==.Burmeister:BAAALgAECgYJDwAAAA==.Burnadine:BAAALgAECgMJAwAAAA==.Burnswhnpee:BAAALgAECggJEwAAAA==.Burtelby:BAAALgADCgYJBgAAAA==.',
['Bû']='Bûrd:BAABLgAECn8bAAQOAAcJAQ9yBwAKAQAOAAYJCgxyBwAKAQADAAUJiQt9TAB/AAAPAAQJWwl9BABwAAAAAA==.',
Ca='Cadsuàne:BAAALgADCgUJCAAAAA==.Caliie:BAAALgAECgYJEQAAAA==.Callira:BAAALgAECgUJDQAAAA==.Cambiare:BAAALgADCgYJCgAAAA==.Canaandra:BAAALgADCgkJBwAAAA==.Captclamslam:BAAALgAECgcJEQAAAA==.Carolline:BAAALgADCgkJCgAAAA==.Catherinecay:BAAALgADCgcJBwAAAA==.',
Ce='Cereania:BAAALgAECgUJDQAAAA==.Cerrabell:BAAALgADCgcJBwAAAA==.',
Ch='Charzzard:BAAALgADCgEJAQAAAA==.Checksmix:BAAALgAECgEJAQAAAA==.Chintakari:BAABLgAECn8VAAMNAAYJ6xKWUwBuAQANAAYJ6xKWUwBuAQALAAEJLwewMAAxAAAAAA==.Chlorofill:BAAALgAECgcJCAAAAA==.Chronologic:BAAALgAECgYJEAAAAA==.',
Co='Cocidiae:BAAALgAECgEJAwAAAA==.Confusious:BAACLgAFFH8GAAIEAAMJkBmsBgDsAAAEAAMJkBmsBgDsAAAuAAQKfyIAAgQACAksE8AOAFQBAAQACAksE8AOAFQBAAAA.Coree:BAABLgAECn8aAAIQAAUJhxDbAgDlAAAQAAUJhxDbAgDlAAAAAA==.Cornflower:BAAALgAECgYJCwAAAA==.Corvaan:BAABLgAECn8ZAAIRAAgJkgyqFABYAQARAAgJkgyqFABYAQAAAA==.',
Cr='Creg:BAAALgAECgYJEQAAAA==.Crowbarr:BAAALgADCgUJBQAAAA==.Cryostatic:BAAALgAECgMJAwABLgAECgYJDgAGAAAAAA==.',
Cu='Cultel:BAABLgAECn8iAAISAAgJ7By2BQBFAgASAAgJ7By2BQBFAgAAAA==.',
Cy='Cyendia:BAAALgAECgUJDgAAAA==.Cyer:BAAALgAECgQJBgAAAA==.',
Da='Daddyraz:BAABLgAECn8VAAIRAAYJthVFHwAPAQARAAYJthVFHwAPAQAAAA==.Dakan:BAAALgADCgkJFgAAAA==.Daphcelyn:BAAALgAECgEJAQAAAA==.Dariusz:BAAALgADCgMJAwAAAA==.Darkalen:BAABLgAECn8aAAITAAcJ8Q+5BwAbAQATAAcJ8Q+5BwAbAQAAAA==.Darklodus:BAAALgADCgcJEwAAAA==.Darriuss:BAAALgAECgQJDgAAAA==.Dathea:BAAALgADCgYJBgAAAA==.Davìd:BAAALgAECgEJAQAAAA==.Dawnmist:BAAALgAECgMJAwAAAA==.Daxetandh:BAAALgAECgIJAgAAAA==.Daxetanir:BAAALgADCgMJAwABLgAECgkJKQAUAEggAA==.Daxetans:BAABLgAECn8pAAMUAAkJSCBKAAATAwAUAAkJSCBKAAATAwAEAAcJPgzcRgBmAQAAAA==.',
De='Deadmoose:BAABLgAECn8jAAIBAAgJwRFbWADpAQABAAgJwRFbWADpAQAAAA==.Deathb:BAAALgADCggJGgAAAA==.Deathjingle:BAABLgAECn8eAAMTAAkJhBokAwDIAQABAAkJmBd8RwAeAgATAAYJhiEkAwDIAQAAAA==.Deecayed:BAAALgAECgYJDQAAAA==.Deecoy:BAAALgAECgUJCQAAAA==.Deestroyer:BAAALgAECgUJCgAAAA==.Deetermined:BAABLgAECn8hAAIEAAgJQh4iAQDEAgAEAAgJQh4iAQDEAgAAAA==.Delion:BAAALgADCgIJAgAAAA==.Demhuloo:BAAALgAECgQJBQAAAA==.Demonburp:BAABLgAECn8WAAIRAAgJ1Bx2OgAKAgARAAgJ1Bx2OgAKAgAAAA==.Denchy:BAAALgAECgYJEAAAAA==.Dendris:BAAALgADCgcJCwAAAA==.Desetraz:BAAALgAECgYJCwAAAQ==.Deval:BAAALgADCgQJBAAAAA==.Deyndine:BAAALgAECgQJCAAAAA==.',
Dh='Dhurza:BAAALgAFFAIJAgAAAA==.',
Di='Disdain:BAAALgAECgYJDAAAAA==.Div:BAABLgAECn8pAAIVAAkJsByHAACcAgAVAAkJsByHAACcAgAAAA==.',
Do='Dogdays:BAAALgADCgkJCQAAAA==.Doki:BAAALgAECgIJAgAAAA==.Dorden:BAABLgAECn8bAAMWAAcJFg/sMQA5AQAWAAcJFg/sMQA5AQAXAAUJQg6/KgAcAQAAAA==.Dorilax:BAAALgAECggJEwAAAA==.Dottarus:BAAALgAECgEJAQAAAA==.',
Dr='Draevus:BAAALgAECgQJBQAAAA==.Dragooniar:BAAALgAECgYJEgAAAA==.Draizen:BAAALgAECgkJBgAAAA==.Dralara:BAAALgADCggJDgAAAA==.Dreàd:BAAALgAECgYJEQAAAA==.Drinna:BAAALgAECgMJBgAAAA==.Drizzette:BAAALgADCgEJAQAAAA==.Droataxh:BAAALgADCgMJAwABLgAECgkJKQADACsfAA==.Droataxm:BAABLgAECn8pAAIDAAkJKx/PAQDSAgADAAkJKx/PAQDSAgAAAA==.Druntress:BAAALgAECgcJEgAAAA==.',
Du='Duarraag:BAAALgADCgIJAQAAAA==.',
['Dà']='Dàvid:BAAALgAECggJCwAAAA==.Dàvìd:BAAALgAECgQJBAAAAA==.',
['Dè']='Dèmonic:BAAALgADCgIJAgAAAA==.',
['Dë']='Dëërez:BAAALgAECgQJCAAAAA==.',
Eb='Eburi:BAAALgAECggJDwAAAA==.',
Ed='Edgybear:BAAALgADCggJCAAAAA==.',
Ei='Eililis:BAAALgAECgMJAwAAAA==.',
El='Elani:BAAALgAECgMJAwABLgAECgUJCQAGAAAAAA==.Elaynaa:BAAALgAECgEJAQAAAA==.Eledweth:BAAALgADCgEJAgAAAA==.Elemengoat:BAAALgADCgQJBAAAAA==.Elfstar:BAAALgADCgUJBQAAAA==.Elihe:BAAALgADCgEJAQAAAA==.Elishaunt:BAAALgAECgQJBwAAAA==.Elivan:BAAALgAECgYJBgAAAA==.Elleth:BAAALgAECgUJDQAAAA==.Eloper:BAAALgAFFAEJAgABLgADCgYJCQAGAAAAAA==.Elvoidra:BAAALgAECgEJAQAAAA==.Elykk:BAAALgAECgYJBgAAAA==.',
Em='Emberana:BAAALgADCgUJBQAAAA==.',
En='Endb:BAAALgADCgYJEAAAAA==.Enjin:BAAALgADCgUJBQAAAA==.Envi:BAAALgADCgUJBQAAAA==.',
Er='Erisaria:BAAALgADCgQJBQAAAA==.Erixi:BAAALgAECgMJBAAAAA==.Erodoreal:BAAALgAECgcJDAAAAA==.',
Et='Etheria:BAAALgAECgQJBAAAAA==.',
Ev='Evocore:BAAALgAECgQJBgAAAA==.',
Ex='Excelimagust:BAAALgAECgIJAgAAAA==.',
Fa='Faithful:BAAALgAECgcJBwAAAA==.Falanor:BAAALgAECgQJBAABLgAECgYJCQAGAAAAAA==.Falcdhruid:BAAALgADCgcJDwAAAA==.Fangrage:BAAALgAECgEJAgAAAA==.Farundi:BAAALgADCgIJAgAAAA==.Fayemoon:BAAALgAECgEJAQAAAA==.',
Fe='Felara:BAAALgAECgYJBgABLgAECggJFAAYACgdAA==.Felbutton:BAAALgAECgQJCAAAAA==.Feldemon:BAAALgAECgQJBQAAAA==.Fellost:BAAALgAECgMJAwABLgAECggJFAAYACgdAA==.Felsen:BAAALgADCgEJAQABLgAECggJFAAYACgdAA==.Felwit:BAABLgAECn8UAAIYAAgJKB0SDwAYAgAYAAgJKB0SDwAYAgAAAA==.Fennec:BAAALgAECgUJCQAAAA==.',
Fh='Fhyn:BAAALgAECgEJAgABLgAECgQJBAAGAAAAAA==.',
Fi='Fitzooth:BAAALgAFFAEJAQAAAA==.',
Fl='Flamos:BAAALgADCgYJBgAAAA==.Florabelle:BAAALgADCgUJCAABLgAECgYJCwAGAAAAAA==.Florid:BAAALgAECgMJAwAAAA==.',
Fo='Foshomomo:BAAALgAECgYJEAAAAA==.Fozzle:BAABLgAECn8ZAAIDAAcJ0guDIwBDAQADAAcJ0guDIwBDAQAAAA==.',
Fr='Fredoku:BAAALgAECgEJAQAAAA==.Frenndi:BAAALgAECgMJAwAAAA==.Frostbites:BAAALgAECgEJAQAAAA==.',
Fy='Fynedge:BAAALgAECgUJDgAAAA==.Fynnyntyss:BAABLgAECn8bAAIZAAcJaQ9QAgByAQAZAAcJaQ9QAgByAQAAAA==.Fyrè:BAABLgAECn8aAAINAAcJayFtDQCcAQANAAcJayFtDQCcAQAAAA==.',
['Fâ']='Fârrah:BAAALgAECgEJAQAAAA==.',
Ga='Gabriels:BAAALgADCgcJDwAAAA==.Gabrielspet:BAAALgADCgIJAgAAAA==.Gainsborough:BAAALgADCgQJBAAAAA==.Galactis:BAAALgAECgQJBQAAAA==.Gavinrad:BAAALgAECgQJBAAAAA==.',
Ge='Gelirri:BAAALgADCgIJAgAAAA==.Getschwiftyy:BAAALgADCgEJAQAAAA==.',
Gi='Githnor:BAABLgAECn8bAAIJAAcJrQbFJAAVAQAJAAcJrQbFJAAVAQAAAA==.',
Go='Goretall:BAAALgADCgYJCAAAAA==.Gothen:BAAALgADCgEJAQAAAA==.',
Gr='Graelyn:BAABLgAECn8XAAMJAAcJLAvtjABhAQAJAAcJVgrtjABhAQAVAAIJQQmRQQA3AAAAAA==.Grimseth:BAAALgADCgUJBQAAAA==.Grimwharf:BAAALgAECgQJBQAAAA==.Grum:BAAALgADCgUJBQAAAA==.Grunaelyn:BAAALgAECgYJDwAAAA==.',
Gu='Guerrier:BAAALgAECgUJBwAAAA==.Gustgut:BAAALgADCggJGgAAAA==.',
Ha='Haelynn:BAAALgADCgcJDAAAAA==.Hahkolhanna:BAAALgADCgcJEgAAAA==.Handrido:BAAALgAECgMJAwAAAA==.Hantaro:BAAALgADCgMJAwAAAA==.Hasuna:BAAALgAECgMJBAAAAA==.',
He='Heikuro:BAAALgAECgYJEQAAAA==.Heris:BAAALgADCgcJDAAAAA==.',
Hi='Hibby:BAAALgAECgMJBAAAAA==.',
Ho='Holymilk:BAAALgAECgIJAgAAAA==.Holysalt:BAAALgADCgUJCwAAAA==.Honadain:BAAALgAECgEJAwAAAA==.Honordin:BAABLgAECn8hAAIJAAgJ0B0GCQD6AQAJAAgJ0B0GCQD6AQAAAA==.Hordestalker:BAAALgAECgQJBwAAAA==.Houllian:BAAALgAECgUJBgAAAA==.',
Hu='Hucha:BAAALgADCgcJBwAAAA==.Hundren:BAAALgAECgEJAQAAAA==.',
Ia='Iamearl:BAAALgADCgYJBwAAAA==.Iamirishgirl:BAAALgADCgIJAgAAAA==.',
Ic='Icyhotness:BAAALgADCgYJBgAAAA==.Icê:BAAALgADCgcJCwAAAA==.',
Ik='Iklyn:BAAALgAECgMJAQAAAA==.',
Il='Illanna:BAAALgADCgIJAgAAAA==.',
Im='Imckickinit:BAAALgAECgQJBAAAAA==.Imorith:BAAALgAECgUJCQAAAA==.',
In='Inania:BAAALgAECggJEwAAAA==.Inception:BAAALgAECgIJAgAAAA==.Incidental:BAABLgAECn8pAAIHAAkJFyQjAABAAwAHAAkJFyQjAABAAwAAAA==.Inconell:BAAALgAECgYJDwAAAA==.',
Ir='Iric:BAAALgAECgEJAQAAAA==.Ironi:BAABLgAECn8eAAMaAAgJCQ+dDgBsAQAaAAcJLQ+dDgBsAQAbAAUJ1QMDbABvAAAAAA==.',
Is='Iskandar:BAABLgAECn8YAAIcAAcJyRb5LQD6AQAcAAcJyRb5LQD6AQAAAA==.',
Iy='Iyashaau:BAAALgADCgYJBgAAAQ==.',
Iz='Izaer:BAAALgAECgUJDQAAAA==.Iziel:BAAALgAECgUJDQAAAA==.',
Ja='Jababa:BAAALgADCgMJAwAAAA==.Jabzaklok:BAAALgAECgcJEAAAAA==.Jahirah:BAABLgAECn8VAAIDAAYJdxRSIQBOAQADAAYJdxRSIQBOAQAAAA==.Janaian:BAABLgAECn8UAAMbAAgJpRCTMgB3AQAbAAcJlxKTMgB3AQAaAAMJ7g3vnACRAAAAAA==.Jarius:BAAALgAECgYJEAAAAA==.',
Je='Jean:BAABLgAECn8cAAINAAgJSxncGABzAgANAAgJSxncGABzAgAAAA==.Jeez:BAAALgAECggJEQAAAA==.Jeri:BAACLgAFFH8MAAMNAAUJ0w4lCgDVAAAIAAQJlgfKEgAPAQANAAMJRBAlCgDVAAAuAAQKfx4AAw0ACAnuIt03AM8BAAgABglVHCkoAOUBAA0ABgnQHt03AM8BAAAA.Jeriaze:BAAALgADCgkJEgAAAA==.',
Jo='Jokuo:BAAALgADCgEJAQAAAA==.Jonyy:BAAALgADCgcJBwAAAA==.Jorianna:BAAALgAECgQJBAAAAA==.Joru:BAACLgAFFH8NAAIdAAYJ9xRGAAARAgAdAAYJ9xRGAAARAgAuAAQKfxYAAh0ACAm9JJYDAPMCAB0ACAm9JJYDAPMCAAEuAAUUBwkOAAgA4xkA.',
Jy='Jynxmaze:BAAALgADCgQJAwAAAA==.',
['Jí']='Jím:BAAALgADCgQJBAABLgAECgYJDwAGAAAAAA==.',
Ka='Kaai:BAAALgAECgUJDQAAAA==.Kabaul:BAABLgAECn8pAAMcAAkJTyElAAAsAwAcAAkJTyElAAAsAwAeAAEJcROLPgA7AAAAAA==.Kabir:BAAALgAECgYJEAAAAA==.Kadria:BAAALgAECgMJBAAAAA==.Kail:BAAALgAECgUJDwAAAA==.Kailanii:BAABLgAECn8UAAMaAAYJ0ROrDwBeAQAaAAYJ0ROrDwBeAQAbAAIJ5QY4dABRAAAAAA==.Kaiscer:BAAALgAECgMJBAAAAA==.Kaitsura:BAAALgADCgUJBQAAAA==.Kaiyne:BAABLgAECn8cAAMKAAgJUhV5UQDTAQAKAAgJUhV5UQDTAQAfAAEJdQ8CcQA1AAAAAA==.Kajiere:BAAALgADCgIJAgAAAA==.Kalagon:BAAALgADCgYJBgAAAA==.Kalakeri:BAAALgADCgMJAwAAAA==.Kalaman:BAAALgAECgUJCQAAAA==.Kalian:BAAALgAECgUJCgAAAA==.Kalito:BAAALgAECgQJCgAAAA==.Kamb:BAAALgAECgYJEQAAAA==.Karalee:BAAALgAECgIJAwAAAA==.Karn:BAAALgADCgEJAQAAAA==.Katieey:BAACLgAFFH8XAAIEAAcJPyUCAAD0AgAEAAcJPyUCAAD0AgAuAAQKfxYAAwQACQnYJMAHAPgCAAQACAmTJMAHAPgCABQABAmiHX07AF8BAAAA.Kayde:BAAALgAECgYJDAAAAA==.Kayil:BAAALgAECgYJBgAAAA==.Kayl:BAABLgAECn8aAAMWAAgJhg1tJwCBAQAWAAgJuwttJwCBAQAZAAQJPxHJKADZAAAAAA==.Kaylli:BAAALgAECgEJAQAAAA==.',
Ke='Kedalin:BAAALgADCgkJGgAAAA==.Keelnin:BAAALgAECgIJBAAAAA==.Keloko:BAAALgAECgQJBgAAAA==.Kennyloggy:BAACLgAFFH8UAAIbAAYJmiPAAABWAgAbAAYJmiPAAABWAgAuAAQKfy4AAhsACQkqJhgAAHADABsACQkqJhgAAHADAAAA.Kevris:BAABLgAECn8VAAIKAAYJyg+9IAAcAQAKAAYJyg+9IAAcAQABLgAECgYJFQADAHcUAA==.Keydan:BAAALgAECgMJBAAAAA==.',
Kh='Khaitiff:BAAALgADCgYJBgAAAA==.Khyn:BAAALgAECgQJBAAAAA==.',
Ki='Killrok:BAAALgADCgUJBQAAAA==.Kinikey:BAAALgADCgkJJgAAAA==.',
Kl='Klassy:BAABLgAECn8iAAILAAgJ4iE+AwD4AgALAAgJ4iE+AwD4AgAAAA==.',
Ko='Koppi:BAAALgAECgMJAwAAAA==.Korru:BAAALgAECgQJCQAAAA==.Kotie:BAABLgAECn8WAAIbAAYJGRX6DAAgAQAbAAYJGRX6DAAgAQAAAA==.',
Kr='Kramz:BAAALgAECggJEAAAAA==.Kronar:BAAALgAECgMJAwAAAA==.',
Ku='Kumojo:BAAALgADCgYJBgAAAA==.Kunka:BAAALgADCgkJCQAAAA==.Kurgan:BAAALgAECgEJAgAAAA==.',
Ky='Kyojin:BAAALgAECgEJAQAAAA==.Kyoshino:BAAALgAECgMJAwAAAA==.Kyrgune:BAAALgADCgkJDgAAAA==.',
['Kî']='Kîkuko:BAAALgADCgYJBgAAAA==.',
['Kÿ']='Kÿliah:BAAALgADCgEJAQAAAA==.',
La='Lalo:BAAALgADCgkJGgAAAA==.Landilion:BAAALgADCgYJBgAAAA==.Laoftey:BAABLgAECn8cAAMEAAgJyBtCGgBGAgAEAAgJyBtCGgBGAgAUAAEJ2Q9GiQAvAAAAAA==.Laofty:BAAALgADCgYJBgAAAA==.Lar:BAAALgADCgEJAgAAAA==.Laserbeam:BAAALgAECgQJBAABLgAECggJFQAKACcgAA==.Lasmori:BAAALgAECgUJCQAAAA==.Lazaris:BAAALgADCgYJBgAAAA==.',
Le='Leglock:BAAALgAECgQJCAAAAA==.Lesbihonest:BAAALgAECgUJDgAAAA==.',
Li='Liendria:BAAALgADCgIJAgAAAA==.Lifensoftpaw:BAACLgAFFH8PAAIMAAUJjBmCAQC9AQAMAAUJjBmCAQC9AQAuAAQKfyAABAwACAkdI1gLAMUCAAwACAkdI1gLAMUCAAcABQl3HKs4AGcBACAAAQm0AapzAB8AAAAA.Lightcaller:BAAALgADCgEJAQAAAA==.Lightflasher:BAAALgAECgcJCgAAAA==.Likkash:BAAALgADCgUJBQABLgAECgcJGgATAPEPAA==.Linthabeela:BAAALgADCgcJDQAAAA==.Lishalthen:BAAALgADCggJCAAAAA==.Lisyanthus:BAAALgADCgEJAgAAAA==.Livicecia:BAAALgAECgcJDwAAAA==.',
Lo='Loaftey:BAAALgADCggJCAAAAA==.Longworth:BAAALgADCgIJAgAAAA==.Lookman:BAAALgAECgYJEAAAAA==.Lothema:BAAALgAECgQJBAAAAA==.',
Lu='Lucaromu:BAAALgAECgEJAQAAAA==.Lucielinna:BAAALgAECgMJAgABLgAECgYJBgAGAAAAAA==.Luckiiem:BAABLgAECn8YAAIDAAgJih0rPgB/AgADAAgJih0rPgB/AgAAAA==.Luisfriendsn:BAAALgADCgEJAQABLgAECgcJHAAPAJMZAA==.Lukian:BAACLgAFFH8IAAIHAAMJCwqFCQDGAAAHAAMJCwqFCQDGAAAuAAQKfyYAAgcACAkoHbQPAKACAAcACAkoHbQPAKACAAAA.Lunabreeze:BAAALgADCgcJBwAAAA==.Lunarkin:BAAALgAECgYJBwAAAA==.Luoma:BAAALgAECgQJCAAAAA==.Luthane:BAAALgAECgYJEAAAAA==.',
Ly='Lyfeliss:BAAALgAECgUJDAAAAA==.',
Ma='Maccolyn:BAABLgAECn8UAAIJAAYJRBfaGgBOAQAJAAYJRBfaGgBOAQAAAA==.Magicpie:BAABLgAECn8gAAIhAAgJ+BuNEQBVAgAhAAgJ+BuNEQBVAgAAAA==.Magiren:BAAALgAECgEJAgAAAA==.Mahlock:BAABLgAECn8iAAIiAAgJKRKjBAC7AQAiAAgJKRKjBAC7AQAAAA==.Makanai:BAAALgAECgUJDQAAAA==.Makenai:BAAALgADCgcJBwABLgAECgUJDQAGAAAAAA==.Makishi:BAAALgAECgYJEAAAAA==.Malferious:BAAALgADCgYJBgAAAA==.Malfura:BAAALgAECgMJBAAAAA==.Malário:BAAALgADCgMJAwAAAA==.Manamontana:BAABLgAECn8XAAIDAAcJaQ4SnACdAQADAAcJaQ4SnACdAQAAAA==.Maplebunny:BAAALgADCgEJAQAAAA==.Mascdomtop:BAABLgAECn8VAAIhAAgJ/h52CADEAgAhAAgJ/h52CADEAgAAAA==.Maube:BAAALgAECgEJAQABLgAFFAIJBgAVAGwUAA==.Mazzarzul:BAAALgAECgUJDgABLgAECggJIgALAJcfAA==.',
Me='Meebles:BAABLgAECn8bAAIjAAcJUg82BgDkAAAjAAcJUg82BgDkAAAAAA==.Meiana:BAABLgAECn8XAAIWAAgJuROSJwCAAQAWAAgJuROSJwCAAQAAAA==.Mekanismz:BAAALgADCgkJCQABLgAECggJHgAcAPgiAA==.Melanthia:BAAALgAECgEJAQAAAA==.Melasmus:BAAALgAECgEJAQAAAA==.Mes:BAAALgAECgYJCQAAAA==.',
Mi='Micklaa:BAAALgAECgYJDQAAAA==.Milan:BAAALgADCgkJCQAAAA==.Milicka:BAAALgADCgkJBwAAAA==.Milkbunny:BAAALgADCgMJAwAAAA==.Millenium:BAAALgAECgQJCgAAAA==.Mingtai:BAAALgAECgYJBwAAAA==.Mirixa:BAAALgADCgYJBgAAAA==.Mizzakien:BAAALgAECgUJBQAAAA==.',
Mo='Monk:BAABLgAECn8aAAIHAAYJ/CT/GQA0AgAHAAYJ/CT/GQA0AgABLgAFFAMJBAAGAAAAAA==.Monkyo:BAAALgAECgcJEAAAAA==.Monrea:BAAALgADCgUJDAABLgAECgEJAwAGAAAAAA==.Moondolli:BAAALgADCgEJAQAAAA==.Moonriver:BAABLgAECn8bAAMEAAcJAQpMWgAfAQAEAAcJAQpMWgAfAQAdAAYJQgWRBwD4AAAAAA==.Moonsinde:BAAALgAECgkJCgAAAA==.Moranta:BAAALgAECgYJDQAAAA==.Moressandra:BAAALgAECgQJCAAAAA==.',
Mu='Murathiel:BAAALgAECgQJBQABLgAECggJGwAgALQkAA==.Murdermass:BAAALgADCgkJDQAAAA==.',
My='Mykellcat:BAAALgAECgMJBAAAAA==.Mysticarc:BAAALgAECggJEQAAAA==.Mysticmurv:BAABLgAECn8ZAAIkAAgJcxy6EABcAgAkAAgJcxy6EABcAgAAAA==.Myvirdaeth:BAAALgADCgEJAQAAAA==.',
Na='Naeni:BAAALgADCgcJDgAAAA==.Nahli:BAAALgAECgQJCAAAAA==.Nakkarn:BAAALgADCgQJBAAAAA==.Nalynahwe:BAAALgAECgYJCwAAAA==.Narima:BAAALgAECgQJCAAAAA==.Naura:BAAALgADCgEJAQAAAA==.Navirose:BAAALgADCgcJEgAAAA==.',
Ne='Neltheron:BAAALgADCgIJAgAAAA==.',
Nh='Nhala:BAAALgAECgEJAQABLgAECgEJAQAGAAAAAA==.',
Ni='Nightestrike:BAAALgADCgQJBAAAAA==.Nikodem:BAAALgAECgYJEwAAAA==.Ninali:BAAALgAECgQJBAAAAA==.Ninerva:BAAALgAECgkJBwAAAA==.',
No='Nore:BAAALgAECgYJDgAAAA==.',
Ny='Nyali:BAAALgAECgEJAQABLgAECgYJFAAaANETAA==.',
['Nà']='Nàdya:BAABLgAECn8hAAIEAAgJRiGCCADtAgAEAAgJRiGCCADtAgAAAA==.',
['Nî']='Nîkodemus:BAAALgADCgYJBgAAAA==.',
Ob='Oblivions:BAABLgAECn8eAAMcAAgJ+CLwCQAQAwAcAAgJ+CLwCQAQAwAeAAEJax07EABXAAAAAA==.Oblivionsdk:BAAALgAECgEJAQABLgAECggJHgAcAPgiAA==.',
Od='Odyfan:BAAALgADCgEJAQAAAA==.',
Of='Ofelia:BAAALgAECgYJDAAAAA==.',
Og='Ogion:BAAALgAECgEJAQAAAA==.',
Om='Omniray:BAAALgAECgYJEAAAAA==.Omnitruce:BAAALgAECgMJAwAAAA==.',
On='Onekark:BAAALgAECgQJCAABLgAFFAUJEQAEAMwaAA==.Onirei:BAAALgADCgEJAwAAAA==.',
Op='Ophèlia:BAAALgADCgIJBwAAAA==.',
Or='Orckus:BAAALgAECgMJAwAAAA==.Oreosbunny:BAAALgADCgYJBgAAAA==.',
Os='Osvaldr:BAAALgAECgQJBQAAAA==.',
Ow='Owil:BAAALgAECggJEQAAAA==.',
Pa='Pandaburn:BAAALgAECgUJCwAAAA==.Pandais:BAAALgAECgQJBQAAAA==.Paranne:BAABLgAECn8bAAIDAAcJEhvCEwCjAQADAAcJEhvCEwCjAQAAAA==.Paroxism:BAABLgAECn8VAAIbAAYJDCQaBADmAQAbAAYJDCQaBADmAQAAAA==.Parthurnax:BAAALgAECgQJBQAAAA==.Patapouf:BAAALgAECgYJEAAAAA==.Patrisse:BAAALgADCgMJAwAAAA==.Pauhana:BAAALgADCgkJDwABLgAECgQJCAAGAAAAAA==.',
Pe='Peanût:BAABLgAECn8cAAIaAAgJXRNvNwDJAQAaAAgJXRNvNwDJAQAAAA==.Pesante:BAABLgAECn8aAAIlAAcJZxuZBQCwAQAlAAcJZxuZBQCwAQAAAA==.',
Ph='Phaket:BAAALgADCgYJBwAAAA==.Phatums:BAACLgAFFH8FAAIBAAIJcRe4NwCsAAABAAIJcRe4NwCsAAAuAAQKfx4AAgEACAmhInsSAA0DAAEACAmhInsSAA0DAAAA.Philippy:BAAALgADCgYJBwAAAA==.',
Pi='Pika:BAAALgAECgYJEAAAAA==.Pinulito:BAAALgADCgMJAwAAAA==.Pippá:BAAALgADCgcJEgAAAA==.',
Po='Polonius:BAAALgAECgUJCwAAAA==.',
Pr='Praline:BAAALgADCgEJAQAAAA==.Pranaverde:BAAALgAECgYJDAAAAA==.Prisevide:BAAALgAECgQJCwAAAA==.Priss:BAAALgADCgcJBwAAAA==.',
Ps='Psyched:BAAALgADCgEJAQAAAA==.',
Pu='Pumpy:BAAALgADCgcJCAAAAA==.',
Py='Pythe:BAABLgAECn8bAAIJAAcJch+rDADKAQAJAAcJch+rDADKAQAAAA==.',
Qa='Qap:BAAALgAECgYJEAAAAA==.Qara:BAAALgADCgYJBgAAAA==.',
Qu='Qualnorr:BAAALgAECgIJAgAAAA==.Queldraayan:BAAALgAECgIJBAAAAA==.Quixediah:BAABLgAECn8cAAIaAAgJ9CGWCQD5AgAaAAgJ9CGWCQD5AgAAAA==.Quixhea:BAAALgAECgQJBwABLgAECggJHAAaAPQhAA==.',
Ra='Radalas:BAAALgAECgQJCAAAAA==.Radreliris:BAAALgAECgEJAQAAAA==.Rahdalas:BAAALgADCgEJAQABLgAECgQJCAAGAAAAAA==.Rally:BAAALgAECgUJDQAAAA==.Ramanujan:BAAALgADCgYJBgAAAA==.Ramcco:BAEALgAECgQJBQAAAA==.Ranelle:BAABLgAECn8bAAIhAAcJShEXCQBsAQAhAAcJShEXCQBsAQAAAA==.Rasmira:BAAALgAECgYJCAAAAA==.Ravenis:BAAALgAECgYJEwAAAA==.Razekial:BAAALgAECgYJCQAAAA==.Razelikh:BAAALgADCgYJBgAAAA==.',
Re='Reedem:BAABLgAECn8UAAIMAAYJdwpKEADOAAAMAAYJdwpKEADOAAAAAA==.Regilock:BAACLgAFFH8RAAQKAAYJyh8hAgAVAgAKAAYJtBohAgAVAgAfAAMJQRYdAQDQAAAmAAEJUwwlBgBTAAAuAAQKfyEABAoACQleJdIIADoDAAoACAkpJdIIADoDAB8ABAnsHhEiAEUBACYAAQkAAOojAGIAAAAA.Regilocklr:BAAALgAECgYJDwAAAA==.Reikí:BAABLgAECn8UAAIDAAYJ4hIrKgAkAQADAAYJ4hIrKgAkAQAAAA==.Relarria:BAAALgADCgMJAwAAAA==.Renbe:BAAALgADCgYJCAAAAA==.Renwald:BAABLgAECn8UAAMJAAYJdhF4kwBWAQAJAAYJdhF4kwBWAQAVAAMJzQo2NAB3AAAAAA==.Revgard:BAAALgAECgUJDQAAAA==.',
Rh='Rhasalgul:BAAALgAECgMJBAAAAA==.',
Ro='Rolhen:BAAALgAECgEJAQAAAA==.Ronso:BAAALgADCgQJBAAAAA==.Ronta:BAAALgADCgYJCgAAAA==.',
Ry='Ryanari:BAAALgAECgQJBQAAAA==.Rylacus:BAAALgAECgMJBAAAAA==.',
['Rê']='Rêgret:BAAALgADCgYJCQAAAA==.',
Sa='Saanda:BAAALgAECgUJBQAAAA==.Sagazboy:BAAALgAECgYJCwABLgAECgcJFgAJAEYRAA==.Sagazpally:BAABLgAECn8WAAIJAAcJRhGDGgBRAQAJAAcJRhGDGgBRAQAAAA==.Salandre:BAAALgADCgMJAwAAAA==.Salutations:BAAALgADCgMJAwABLgAECgkJKgAFAD0QAA==.Salv:BAAALgADCgIJAgAAAA==.Sandp:BAAALgAFFAEJAQAAAA==.Sapphin:BAAALgADCgQJBAAAAA==.Sarlef:BAAALgAECgUJDgAAAA==.Sashafel:BAAALgADCggJCAAAAA==.',
Sc='Scarm:BAAALgADCgUJCgAAAA==.Scyithe:BAAALgADCgEJAQAAAA==.',
Se='Sellidra:BAAALgAECgQJCAAAAA==.Sendcatpics:BAABLgAECn8qAAMFAAkJPRCEBQAGAgAFAAkJPRCEBQAGAgAJAAUJBBrvgwByAQAAAA==.Seo:BAAALgAFFAIJAgAAAA==.Serenitara:BAAALgADCgYJBgAAAA==.Sethia:BAAALgADCgQJBAABLgADCgUJBQAGAAAAAA==.Sevotarthe:BAAALgADCgMJAwAAAA==.Seyana:BAAALgAECgUJCQAAAA==.',
Sh='Shadowkaos:BAAALgAECgUJCAAAAA==.Shaffer:BAAALgAECgYJCwAAAA==.Shellmage:BAAALgAECgQJBgAAAA==.Shellshocker:BAABLgAFFH8GAAIUAAMJPSDwCwAtAQAUAAMJPSDwCwAtAQAAAA==.Shermantånk:BAAALgADCgYJDwAAAA==.Sheydon:BAAALgADCgQJBAAAAA==.Shiftstain:BAAALgADCgIJAgAAAA==.Shikï:BAABLgAECn8dAAInAAgJ0R/+DQCjAgAnAAgJ0R/+DQCjAgAAAA==.Shivermoón:BAABLgAECn8ZAAIaAAgJWwt0DwBhAQAaAAgJWwt0DwBhAQAAAA==.Shobek:BAAALgAECgYJBgAAAA==.Shortie:BAAALgADCgYJBgAAAA==.',
Si='Sigesar:BAAALgAECgYJEQAAAA==.Silvaria:BAAALgAECgMJBAAAAA==.Simina:BAAALgAECgEJAQAAAA==.Simura:BAAALgAECgcJDQAAAA==.Sinamara:BAAALgADCgYJEwAAAA==.Sinsimella:BAAALgADCgYJCAAAAA==.Sinõn:BAAALgAECgEJAQAAAA==.',
Sk='Skyliner:BAAALgAECgQJBQAAAA==.Skyskitty:BAAALgAECgYJCwAAAA==.Skywatcher:BAAALgAECgYJEAAAAA==.',
Sl='Slaughtering:BAAALgAECgUJDQAAAA==.',
Sm='Smesus:BAAALgAECgEJAQAAAA==.Smitemare:BAAALgAECgMJAwAAAA==.',
So='Solare:BAAALgADCgYJCgAAAA==.Solianti:BAAALgADCgYJBgAAAA==.Solodan:BAAALgAECgYJDAAAAA==.Sonnwar:BAABLgAECn8bAAIFAAgJ+hpwCAC/AQAFAAgJ+hpwCAC/AQAAAA==.',
Sp='Spliphtoker:BAAALgAECgMJAwAAAA==.Spookytotems:BAABLgAECn8eAAIdAAcJyxU1AwCiAQAdAAcJyxU1AwCiAQAAAA==.',
St='Stenston:BAAALgAECgYJBgAAAA==.Sterede:BAAALgADCgkJFwAAAA==.Stonehenge:BAAALgAECgQJCAAAAA==.Stormb:BAAALgADCgkJEQAAAA==.Stormwolves:BAAALgADCgcJBwAAAA==.',
Sy='Sylphr:BAAALgAECgQJBwAAAA==.Sylphwild:BAAALgAECgIJAgAAAA==.Sylvanase:BAAALgAECgcJCgAAAA==.Synapze:BAAALgAECgYJEAAAAA==.Syreite:BAABLgAECn8UAAIjAAYJTRXkBAAfAQAjAAYJTRXkBAAfAQAAAA==.Syreyna:BAAALgADCgIJAgAAAA==.',
Ta='Taessa:BAAALgADCggJBAAAAA==.Tahwye:BAAALgADCgYJFwAAAA==.Tainipuni:BAAALgAECgQJBwAAAA==.Takemi:BAAALgADCgIJAgAAAA==.Tallac:BAAALgADCgYJBgABLgAECggJIgAVADkVAA==.Tallaric:BAAALgADCgkJFAABLgAECggJIgAVADkVAA==.Tallic:BAABLgAECn8iAAIVAAgJORWUDwDLAQAVAAgJORWUDwDLAQAAAA==.Tamarah:BAAALgAECgQJBAAAAA==.Tamzyyn:BAAALgAECgMJBAAAAA==.Tandemonium:BAAALgAECgEJAQABLgAFFAMJBgAkANEcAA==.Taniz:BAAALgAECggJEwAAAA==.Tankfu:BAAALgAECgEJAQAAAA==.Tarsi:BAAALgAECgQJCAAAAA==.Tashoonne:BAAALgADCgUJBwAAAA==.',
Te='Teareagana:BAAALgAECgYJCgABLgAECggJEQAGAAAAAA==.Tearinurside:BAAALgAECgUJDQAAAA==.Teddy:BAAALgADCgUJBQABLgAECgcJHQAgACsgAA==.Telchar:BAAALgAECgQJBAAAAA==.Telidrel:BAAALgADCgMJAwAAAA==.Teratin:BAABLgAECn8VAAIHAAYJCR9/BwCDAQAHAAYJCR9/BwCDAQAAAA==.Tevellan:BAAALgADCgYJBwAAAA==.',
Th='Thaddeaus:BAABLgAECn8VAAIYAAgJJRgcDQA6AgAYAAgJJRgcDQA6AgAAAA==.Thaddeus:BAAALgAECgYJEQAAAA==.Thauris:BAAALgAECgEJAQAAAA==.Thealin:BAAALgAECgMJAwAAAA==.Thebeefyone:BAAALgAECgUJCQAAAA==.Thelesar:BAAALgADCgYJCAAAAA==.Therizin:BAAALgAECgUJDAAAAA==.Thesummoner:BAABLgAECn8VAAMKAAgJJyDVEwDeAgAKAAgJJyDVEwDeAgAfAAEJxxVPawA8AAAAAA==.Thicciana:BAAALgAECgYJDAAAAA==.Thorizan:BAAALgAECgQJBwAAAA==.Thugnificent:BAAALgADCgcJBwAAAA==.Thumpette:BAAALgADCgMJAwAAAA==.Thè:BAAALgAECgYJCwAAAA==.',
Ti='Tierant:BAAALgAECgEJAQAAAA==.Tituz:BAAALgADCgMJBAAAAA==.Tizaria:BAAALgAECgUJCQAAAA==.',
Tm='Tmai:BAAALgAECgUJDQAAAA==.',
To='Tolken:BAAALgAECgEJAQAAAA==.Tominaetor:BAAALgAECgUJEQAAAA==.Tosoto:BAAALgAECgcJEwAAAA==.Toxerus:BAAALgAECgMJBAAAAA==.',
Tr='Trixigossa:BAAALgADCggJEgABLgAECgEJAQAGAAAAAA==.Trobbio:BAAALgADCgIJAgAAAA==.',
Ts='Tso:BAAALgAECgYJDAAAAA==.Tsukuyomï:BAAALgAECgIJAwABLgAECggJHQAnANEfAA==.',
Tu='Tuskmunkey:BAAALgAECgMJAwAAAA==.',
Ty='Tyernan:BAABLgAECn8aAAMFAAcJSgT5EQAhAQAFAAcJSgT5EQAhAQAJAAIJyAQbJwFRAAAAAA==.Tym:BAAALgADCgkJDAAAAA==.Tyrael:BAABLgAECn8eAAIJAAYJxwpIpAA4AQAJAAYJxwpIpAA4AQAAAA==.Tyreanna:BAAALgADCgEJAgAAAA==.Tyrioz:BAABLgAECn8VAAMFAAYJCBBOEwANAQAFAAYJCBBOEwANAQAJAAIJ5REcFAFvAAAAAA==.',
Tz='Tzavcat:BAAALgAECgQJDAAAAA==.',
Ul='Uluhn:BAAALgADCggJDgABLgAECgEJAQAGAAAAAA==.',
Ur='Urklesnurkle:BAAALgAECgEJAwAAAA==.',
Uv='Uvsol:BAAALgAECgIJAgAAAA==.',
Va='Vadailla:BAAALgADCgYJCQABLgAECgQJCAAGAAAAAA==.Vahrik:BAAALgAECgEJAQAAAA==.Valcane:BAAALgADCgkJEgAAAA==.Valius:BAAALgAECgUJDgAAAA==.Vallarium:BAAALgADCgUJDgAAAA==.Valornor:BAAALgAECgIJAgAAAA==.Valyerian:BAAALgAECgUJBgAAAA==.Vanacarde:BAAALgAECgUJBQAAAA==.Vandilious:BAAALgAECgQJBAABLgAECgUJCAAGAAAAAA==.Vandill:BAAALgAECgUJCAAAAA==.Vaneadra:BAAALgADCgUJCgAAAA==.Vankro:BAABLgAECn8kAAISAAgJliUsAADfAgASAAgJliUsAADfAgAAAA==.',
Ve='Veasnacool:BAAALgAECggJDwAAAA==.Velanlan:BAAALgADCgUJBQAAAA==.Velion:BAAALgADCgYJBgAAAA==.',
Vh='Vhesper:BAAALgADCggJDQAAAA==.',
Vi='Vii:BAAALgAECgYJCwAAAA==.',
Vo='Voidfisting:BAABLgAECn8fAAMgAAgJEgfTMwAmAQAgAAgJEgfTMwAmAQAMAAEJvAHXJQAlAAAAAA==.Volfurion:BAAALgADCgQJBAAAAA==.Vontote:BAAALgAECgUJBgAAAA==.Vorix:BAAALgAECgQJBwAAAA==.Vorrel:BAAALgADCgkJFwABLgAECggJGgAWAIYNAA==.',
Vu='Vunak:BAAALgADCgcJDQAAAA==.',
['Ví']='Víc:BAAALgAECgYJDAAAAA==.',
Wa='Wandorf:BAEALgAECgYJEQAAAA==.Warbacon:BAAALgADCgMJAwAAAA==.Wargyle:BAAALgAECgYJEQAAAA==.Warwolfe:BAABLgAECn8cAAMmAAcJEgfwFgDIAAAKAAcJpwXtLQDQAAAmAAQJ+QfwFgDIAAAAAA==.Wayler:BAAALgAECgIJAgAAAA==.',
We='Wealthywolf:BAAALgAECgYJDwAAAA==.Werepinguin:BAAALgADCgMJAwAAAA==.',
Wi='Wilbrew:BAAALgADCgUJCgABLgAECggJEQAGAAAAAA==.Wistful:BAAALgAECgIJAgAAAA==.',
Wl='Wlitia:BAAALgADCgkJEwAAAA==.',
Wo='Wolferunner:BAAALgAECgQJCAAAAA==.',
Wr='Wrathome:BAABLgAECn8cAAMKAAcJgxqxQAALAgAKAAcJgxqxQAALAgAfAAMJtgrIRgCbAAAAAA==.',
Xa='Xalatäth:BAAALgAECgMJBAAAAA==.Xaldora:BAAALgADCgcJDwAAAA==.Xandrake:BAAALgAECgYJDAABLgAFFAUJCQAWAIcZAA==.',
Xd='Xdxvuu:BAAALgAECgYJDQAAAA==.',
Xe='Xerimok:BAAALgAECgMJBAAAAA==.',
Xi='Xinya:BAAALgADCgkJFgAAAA==.Xipa:BAABLgAECn8XAAIIAAgJ6hgaHwAqAgAIAAgJ6hgaHwAqAgAAAA==.',
Xl='Xladykahlron:BAAALgADCgYJCAAAAA==.',
Xs='Xshan:BAAALgAECgEJAgAAAA==.Xshando:BAAALgAECgQJBwAAAA==.',
Xy='Xyi:BAAALgAECgYJCgAAAA==.',
Xz='Xzephyr:BAABLgAECn8bAAIbAAcJACEnBADkAQAbAAcJACEnBADkAQAAAA==.',
Ya='Yamato:BAAALgAECgcJEQAAAA==.',
Ye='Yesmín:BAAALgAECgMJBAAAAA==.',
Yo='Youwas:BAAALgAECgcJCgAAAA==.Yoveladari:BAAALgADCgIJAgAAAA==.',
Yu='Yukimenoko:BAAALgAECgUJDAAAAA==.Yukmouf:BAABLgAECn8UAAIJAAgJ2BtpIwCbAgAJAAgJ2BtpIwCbAgAAAA==.',
Za='Zabrak:BAAALgADCgkJGgAAAA==.Zakaris:BAAALgADCgIJAgAAAA==.Zalaeran:BAAALgADCgEJAQAAAA==.Zalatath:BAAALgADCgkJHgAAAA==.Zarrov:BAAALgADCgkJGgAAAA==.Zarrove:BAABLgAECn8fAAIMAAgJRiAQCQDnAgAMAAgJRiAQCQDnAgAAAA==.',
Ze='Zea:BAAALgAECgEJAQAAAA==.Zedael:BAABLgAECn8VAAITAAYJWBh2GgB9AQATAAYJWBh2GgB9AQAAAA==.Zeltri:BAAALgADCgUJBQAAAA==.',
Zh='Zhatva:BAAALgAECgcJEwAAAA==.Zhöe:BAAALgAECggJEwAAAA==.',
Zo='Zoldor:BAAALgAECgYJDwAAAA==.Zoleia:BAAALgADCgIJAgAAAA==.Zoral:BAAALgADCgUJBQAAAA==.',
Zu='Zuldokah:BAAALgADCgEJAQAAAA==.',
Zy='Zy:BAAALgADCgkJFAAAAA==.Zycorr:BAAALgAECgEJAQAAAA==.Zyheal:BAAALgAECgYJCgAAAA==.Zymor:BAAALgAECgMJAwAAAA==.Zytrex:BAAALgADCgcJBwAAAA==.',
['Äm']='Ämaterasu:BAAALgADCgcJCgABLgAECggJHQAnANEfAA==.',
['Ða']='Ðaniel:BAAALgAECgYJDQAAAA==.',
['Ðr']='Ðraevus:BAAALgAECgQJDAAAAA==.',
['Ñÿ']='Ñÿx:BAAALgAECgUJCwAAAA==.',
['ßl']='ßlueshield:BAAALgAECgYJDAAAAA==.',
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
