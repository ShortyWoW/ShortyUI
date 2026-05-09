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

local lookup = {'DeathKnight-Unholy','Hunter-BeastMastery','DemonHunter-Devourer','Mage-Frost','Monk-Brewmaster','Warrior-Arms','DeathKnight-Blood','Rogue-Subtlety','Monk-Windwalker','Unknown-Unknown','Evoker-Preservation','DemonHunter-Vengeance','Druid-Restoration','Druid-Guardian','Warlock-Demonology','Rogue-Assassination','Shaman-Enhancement','Evoker-Devastation','Evoker-Augmentation','Shaman-Elemental','Warlock-Destruction','Warrior-Protection','Druid-Balance','Priest-Holy','Druid-Feral','Paladin-Retribution','Shaman-Restoration','Monk-Mistweaver','Priest-Shadow','DemonHunter-Havoc','Mage-Fire','Mage-Arcane','Priest-Discipline','Paladin-Holy','Warrior-Fury','Warlock-Affliction','Hunter-Survival','Hunter-Marksmanship','Paladin-Protection',}
local provider = {region='US',realm="Lightning'sBlade",name='US',type='weekly',zone=46,date='2026-05-08',data={Ad='Aderai:BAAALgADCgYJCgAAAA==.',
Ae='Aeliong:BAAALgAECgEJAQAAAA==.Aendronys:BAAALgADCgQJAwAAAA==.',
Af='Afterparty:BAAALgAECggJEwAAAA==.',
Ag='Aguni:BAAALgAECggJEAABLgAFFAMJBwABADQVAA==.',
Ah='Ahmin:BAAALgADCgYJBgAAAA==.',
Ai='Aiura:BAAALgAECgYJCgAAAA==.',
Aj='Ajunlucky:BAACLgAFFH8NAAICAAQJPhlVEABYAQACAAQJPhlVEABYAQAuAAQKfzAAAgIACQkpIk0CACcDAAIACQkpIk0CACcDAAAA.',
Al='Alagondar:BAAALgAECgYJEgAAAA==.Alakard:BAABLgAECn8XAAIDAAgJ6xjAFwD+AQADAAgJ6xjAFwD+AQAAAA==.Alberich:BAAALgAECgcJDwAAAA==.Alexari:BAAALgADCgcJCwAAAA==.Alexthejoker:BAAALgADCgQJAwAAAA==.Alody:BAAALgADCgMJAwAAAA==.Althenath:BAAALgADCgMJBAAAAA==.',
Am='Amalica:BAABLgAECn8WAAIEAAUJ7SCBXgBVAQAEAAUJ7SCBXgBVAQAAAA==.Amenadiel:BAAALgAECgcJEQAAAA==.Amuyal:BAAALgADCgYJBgAAAA==.',
An='Anaphylactic:BAAALgAECgYJBQAAAA==.Andrea:BAABLgAECn8VAAIFAAYJvBIRIQAwAQAFAAYJvBIRIQAwAQAAAA==.Angelline:BAAALgAECgUJCgABLgAFFAMJCgAGAD4lAA==.Antimagi:BAAALgADCgkJCQAAAA==.',
Ap='Apheelia:BAAALgAECgQJDAAAAA==.Appypie:BAABLgAECn8kAAIHAAkJkw+PDQCYAQAHAAkJkw+PDQCYAQAAAA==.',
Ar='Arale:BAAALgAECgEJAQAAAA==.Aramala:BAAALgAECgIJAwAAAA==.Arkveld:BAABLgAECn8rAAIIAAgJWiOVAgDHAgAIAAgJWiOVAgDHAgAAAA==.',
As='Ashurasenku:BAAALgAECgkJDwAAAA==.Asten:BAAALgAECgMJBgAAAA==.',
At='Athair:BAABLgAECn8fAAIJAAYJMx8FDwDKAQAJAAYJMx8FDwDKAQAAAA==.Athineana:BAAALgAECgQJBAAAAA==.',
Au='Augtistic:BAAALgAECgUJBQABLgAFFAEJAQAKAAAAAA==.Aulken:BAAALgADCgEJAQAAAA==.',
Ay='Aylinn:BAABLgAECn8fAAILAAgJ5BxwBABsAgALAAgJ5BxwBABsAgAAAA==.Aylira:BAAALgAECgQJCAAAAA==.Aymonzo:BAABLgAECn8aAAMDAAgJERZtOABUAQADAAgJERZtOABUAQAMAAEJFBRxHQA6AAAAAA==.',
Az='Azem:BAAALgADCgkJDAAAAA==.',
Ba='Badlóck:BAAALgAECgcJBgABLgAECgkJAQAKAAAAAA==.Baharrar:BAACLgAFFH8LAAINAAQJ+hn6DwBVAQANAAQJ+hn6DwBVAQAuAAQKfygAAw0ACQkYImIFAAIDAA0ACQkYImIFAAIDAA4AAQn9EjQoADcAAAAA.Barofslovr:BAAALgADCgcJBwABLgAECgYJEQAKAAAAAA==.Barrylowmana:BAAALgADCgcJBwAAAA==.Bartendresse:BAAALgAECgEJAQAAAA==.Bastrasz:BAAALgAECgcJCwAAAA==.Batar:BAAALgADCgYJBgAAAA==.',
Be='Bearalas:BAACLgAFFH8NAAIPAAUJ+RRcKgAbAQAPAAUJ+RRcKgAbAQAuAAQKfxUAAg8ACQmqG/QYAL8CAA8ACQmqG/QYAL8CAAAA.Bearis:BAAALgADCgMJAwAAAA==.Beekin:BAAALgAECgUJCwAAAA==.Beeyah:BAABLgAECn8hAAICAAgJ9x/7DAB1AgACAAgJ9x/7DAB1AgAAAA==.Beldion:BAAALgADCgUJBQABLgAECgYJGwAFALYVAA==.Bellator:BAAALgADCgMJAwAAAA==.Bellona:BAAALgADCgQJBAAAAA==.Bernarnold:BAAALgAECgYJEAAAAA==.Bettyspready:BAABLgAECn8VAAIQAAgJ/w5hBQCmAQAQAAgJ/w5hBQCmAQAAAA==.',
Bi='Bigoysters:BAAALgAECgMJBAAAAA==.Bigpoppapump:BAABLgAECn8fAAIRAAYJxSa5AwBAAgARAAYJxSa5AwBAAgAAAA==.Bigthumbb:BAAALgAECgEJAQAAAA==.Bigvikingg:BAAALgAECgcJAwAAAA==.Bikook:BAAALgADCgIJAgABLgAECgkJHQALACgPAA==.Binnyi:BAABLgAECn8mAAMSAAgJuA1gBQCKAQASAAgJuA1gBQCKAQATAAYJogbpPAD6AAAAAA==.Biwwy:BAAALgAECgEJAQAAAA==.',
Bl='Blabidil:BAAALgADCgQJBAAAAA==.Blackfoot:BAABLgAECn8XAAIUAAkJpBWxEADcAQAUAAkJpBWxEADcAQAAAA==.Blackyeshua:BAACLgAFFH8MAAITAAMJzhB6IADqAAATAAMJzhB6IADqAAAuAAQKfy4AAhMACQl1HvgFAIICABMACQl1HvgFAIICAAAA.Blastphemy:BAAALgADCgYJBgAAAA==.Blindpov:BAAALgADCggJCQAAAA==.',
Bo='Boanhead:BAAALgADCgIJAgAAAA==.Bogorline:BAAALgADCgQJBAAAAA==.Boomtiloom:BAAALgADCgMJAwAAAA==.Borgastraz:BAABLgAECn8VAAQSAAYJhA+jCwDcAAASAAUJzQ2jCwDcAAATAAQJDgx8QQCUAAALAAIJEAzgIABkAAAAAA==.Boru:BAAALgADCgcJBwAAAA==.Boshin:BAAALgAECgEJAQAAAA==.Boshintime:BAAALgAECgMJAwAAAA==.Bouberry:BAABLgAECn8XAAIVAAYJWx6mCABQAQAVAAYJWx6mCABQAQAAAA==.',
Br='Brewstoes:BAAALgADCgQJBQAAAA==.Bricksquadx:BAAALgAECgMJBQAAAA==.Brink:BAAALgADCgMJAwAAAA==.Broki:BAAALgAECgEJAgAAAA==.Brugnir:BAAALgAECgYJBgABLgAECgUJBwAKAAAAAA==.Bruwen:BAAALgAFFAEJAQAAAA==.',
Bu='Bubblegruff:BAAALgADCgkJGQAAAA==.Bubbleohsevn:BAAALgAECgcJDwAAAA==.Bubblesaurus:BAABLgAECn8eAAMTAAcJhxfMGAB6AQATAAcJ4hXMGAB6AQASAAYJrg9zIQAgAQAAAA==.Bum:BAAALgADCgkJCQAAAA==.Burlan:BAAALgAECgYJEgAAAA==.',
['Bé']='Béåst:BAAALgAECgYJDwAAAA==.',
['Bë']='Bërshton:BAAALgAECgYJCAAAAA==.',
Ca='Cakeshake:BAABLgAECn8UAAICAAYJIhK7RwA2AQACAAYJIhK7RwA2AQAAAA==.Caleris:BAABLgAECn8iAAIWAAkJNxleBQBMAgAWAAkJNxleBQBMAgAAAA==.Camelnuckle:BAABLgAECn8jAAIUAAgJMBagFwCUAQAUAAgJMBagFwCUAQAAAA==.Car:BAAALgADCgIJAgAAAA==.Cattle:BAABLgAECn8WAAIXAAkJAxFQFwCBAQAXAAkJAxFQFwCBAQAAAA==.',
Ch='Chaosglaive:BAAALgAECgcJEgAAAA==.Chaostorms:BAAALgAECgcJEwAAAA==.Chess:BAAALgAECgYJCwAAAA==.Chickenhydra:BAAALgADCgYJBgAAAA==.Chlorophil:BAAALgADCgYJBwAAAA==.Choochew:BAAALgAECgEJAgAAAA==.Chowlock:BAABLgAECn8iAAMVAAkJcyPaAgDTAgAVAAcJniPaAgDTAgAPAAUJmSJeUwAxAQAAAA==.Chowmantwo:BAAALgADCgEJAQAAAA==.Chronical:BAAALgADCgcJBwAAAA==.',
Cl='Classicmonk:BAAALgAECgQJBQAAAA==.Clawsofpeace:BAAALgADCgkJDQABLgAECggJIQAYAGEOAA==.Cleverboi:BAAALgADCgYJBgAAAA==.',
Co='Conlord:BAABLgAECn8XAAIBAAYJ5SOIIAAHAgABAAYJ5SOIIAAHAgAAAA==.Constancia:BAAALgAECgUJDQAAAA==.',
Cr='Crackahjack:BAAALgAECgEJAQAAAA==.Craigor:BAAALgAECgEJAQABLgAECggJEwAKAAAAAA==.Croppydust:BAAALgADCgcJDAAAAA==.Cryden:BAAALgADCgMJAwAAAA==.',
Cy='Cylicmylic:BAAALgAECgQJBAAAAA==.',
Cz='Czark:BAAALgAECgQJBAAAAA==.',
Da='Dalamaar:BAAALgADCgEJAQAAAA==.Dampundies:BAAALgAECgEJAQAAAA==.Dandey:BAAALgAECgYJBwAAAA==.Dangerdoom:BAAALgAECgIJAwABLgAECggJIQAEAJwXAA==.Dantee:BAABLgAECn8nAAIMAAgJCx50AgBXAgAMAAgJCx50AgBXAgAAAA==.Daps:BAAALgADCgcJCgAAAA==.Darkfoxgrime:BAABLgAECn8bAAIJAAkJIg0VEAC8AQAJAAkJIg0VEAC8AQAAAA==.Dartini:BAAALgAECgIJAgAAAA==.Datsmywife:BAABLgAECn8ZAAMZAAcJTRCJEQCVAQAZAAcJTRCJEQCVAQAXAAUJYAWEOwCZAAAAAA==.Davis:BAAALgAECgkJEAAAAA==.Daytimes:BAAALgAECgIJAgAAAA==.Daytknight:BAAALgAECgMJAwAAAA==.',
De='Deadvikingg:BAAALgAFFAMJAwAAAA==.Deadwix:BAAALgADCgMJAwAAAA==.Deebss:BAAALgAECgEJAQAAAA==.Degradation:BAAALgAECgEJBQAAAA==.Degru:BAAALgAECgYJDgABLgAECggJCAAKAAAAAA==.Delaire:BAAALgAECgYJDwAAAA==.Demenhunta:BAAALgAECgMJAgAAAA==.Demonkow:BAACLgAFFH8PAAIPAAQJnhiqHgA7AQAPAAQJnhiqHgA7AQAuAAQKfyEAAw8ACQlRIt8TAEICAA8ACAkXIt8TAEICABUABAkPIgYbAHUBAAAA.Dereksama:BAAALgADCgQJBAAAAA==.Destrah:BAAALgADCgUJBQAAAA==.Deviiarrc:BAACLgAFFH8QAAILAAQJLiKTCACSAQALAAQJLiKTCACSAQAuAAQKfycAAgsACAlYJSEDADUDAAsACAlYJSEDADUDAAAA.',
Di='Dikan:BAAALgADCgEJAQAAAA==.Dinosaurman:BAAALgAECgQJBAAAAA==.Disintegrate:BAAALgAECgcJBwABLgAFFAUJEwATAMwaAA==.',
Do='Doova:BAAALgADCgYJCgAAAA==.Dorik:BAAALgADCgYJBgAAAA==.',
Dr='Dracar:BAABLgAECn8aAAIaAAgJmBWoLgDCAQAaAAgJmBWoLgDCAQAAAA==.Drackian:BAAALgAECgQJBAAAAA==.Dragondyne:BAAALgAECggJCAABLgAECgkJOQAFAN4aAA==.Drdurun:BAAALgADCgYJBwAAAA==.Drekavak:BAAALgAECgYJCAAAAA==.Drekfur:BAAALgAECgQJBAAAAA==.Drmmrfist:BAABLgAECn8tAAIFAAkJERarCgAYAgAFAAkJERarCgAYAgAAAA==.Druideca:BAAALgAECgYJDgAAAA==.',
Dw='Dwippietiggs:BAABLgAECn8tAAIaAAkJwiB2BQD3AgAaAAkJwiB2BQD3AgAAAA==.',
Ea='Earthfeather:BAAALgAECgEJAQAAAA==.',
Ec='Echoesonmute:BAAALgADCgEJAQAAAA==.',
Ed='Edhochuli:BAAALgADCgUJBQABLgAECgYJCwAKAAAAAA==.',
Ee='Eetee:BAABLgAECn8jAAQUAAgJkBGDKwC7AQAUAAgJkBGDKwC7AQARAAQJNQvIHwDVAAAbAAUJIw1EUgC1AAAAAA==.',
Ek='Ekitten:BAAALgAECgYJCwABLgAFFAQJCQAcAO8kAA==.',
El='Elandria:BAAALgAECgYJEAAAAA==.Elohym:BAAALgADCgUJBQAAAA==.Elsea:BAAALgAECgQJCgAAAA==.',
Em='Emberstone:BAAALgAECgEJAQAAAA==.Emerys:BAAALgAECgYJBgAAAA==.Emotions:BAABLgAECn8VAAIDAAgJWhISMQByAQADAAgJWhISMQByAQAAAA==.',
Ep='Epicdragon:BAAALgAECgYJBwAAAA==.',
Eq='Equesmortis:BAAALgAECgYJDgAAAA==.',
Er='Erös:BAAALgAECgUJDgAAAA==.',
Et='Etatoned:BAAALgAECgYJDQAAAA==.Etengaged:BAAALgAECgYJDQAAAA==.Ethavoc:BAAALgADCgQJBAAAAA==.Ethuln:BAAALgADCgIJAgAAAA==.',
Eu='Eurdice:BAAALgADCgIJAgAAAA==.',
Ev='Evo:BAAALgAECgMJAwABLgAECggJKwAEAMQdAA==.Evrae:BAABLgAECn8WAAIIAAcJlxJzEACgAQAIAAcJlxJzEACgAQAAAA==.',
Ex='Extragrace:BAABLgAECn8VAAIEAAYJHQPOrQC4AAAEAAYJHQPOrQC4AAAAAA==.',
Fa='Faithshand:BAABLgAECn8mAAMYAAgJmQr7IwAqAQAYAAgJmQr7IwAqAQAdAAUJewNhMgDHAAAAAA==.Fallenbow:BAAALgAECgUJBgAAAA==.Fappa:BAABLgAECn8vAAIPAAkJrBMQGQAbAgAPAAkJrBMQGQAbAgAAAA==.',
Fe='Featherstone:BAAALgADCgIJAwAAAA==.Feelzdope:BAAALgADCgQJBAAAAA==.Feio:BAABLgAECn8lAAIeAAgJiR8eBQBqAgAeAAgJiR8eBQBqAgAAAA==.Felfirez:BAAALgAECgEJAQAAAA==.Fellhock:BAAALgAECgMJAwAAAA==.Felydrak:BAABLgAECn8aAAQSAAgJ1hSEDQABAgASAAgJshOEDQABAgALAAMJowavHwBtAAATAAIJZgy2SgBoAAAAAA==.Fergilicious:BAAALgAECgYJEQAAAA==.',
Fi='Finkenator:BAACLgAFFH8VAAIEAAYJBxukCwDJAQAEAAYJBxukCwDJAQAuAAQKfyYAAgQACQl/I70KAG4DAAQACQl/I70KAG4DAAAA.Finkler:BAACLgAFFH8IAAIEAAQJjRtAIABoAQAEAAQJjRtAIABoAQAuAAQKfywAAgQACQnqIsAOAFEDAAQACQnqIsAOAFEDAAEuAAUUBgkVAAQABxsA.Firedanny:BAAALgAECgUJCwAAAA==.',
Fl='Flameshock:BAABLgAECn8oAAQfAAkJZBB1AgCZAQAfAAkJMAt1AgCZAQAgAAQJKhAKBgD/AAAEAAQJdwOLJwGyAAAAAA==.Flippybippi:BAAALgAECgEJAQAAAA==.Flixur:BAACLgAFFH8PAAIEAAQJtRBxMQBGAQAEAAQJtRBxMQBGAQAuAAQKfx8AAgQABwnnHwQnAAcCAAQABwnnHwQnAAcCAAAA.Fluffyduck:BAAALgADCgMJAwAAAA==.Flyzikman:BAAALgADCgEJAQAAAA==.',
Fo='Forestdump:BAAALgADCgYJBgABLgAECgYJCwAKAAAAAA==.Forté:BAAALgADCgMJAwAAAA==.',
Fr='Freek:BAAALgAECgEJAgABLgAECgUJBwAKAAAAAA==.Freewillie:BAAALgAECgEJAgABLgAECgQJBgAKAAAAAA==.Friarmj:BAABLgAECn8uAAIhAAkJUQ3FDQD0AQAhAAkJUQ3FDQD0AQAAAA==.Frigidbeach:BAAALgAECgYJDwAAAA==.Frozeny:BAAALgADCgcJDQAAAA==.',
Fu='Furrita:BAAALgADCgcJBwAAAA==.',
Ga='Galazeth:BAAALgAECgcJEAABLgAFFAMJBwABADQVAA==.Gamthor:BAAALgAECggJEwAAAA==.',
Ge='Germz:BAAALgAECgkJBwAAAA==.',
Gi='Gildeddash:BAAALgAECgYJDwAAAA==.Giudice:BAAALgAECgIJAgAAAA==.',
Gl='Glengoyne:BAAALgAECgQJDAAAAA==.Globoe:BAACLgAFFH8bAAMSAAgJcx5FAAD/AQASAAUJeyRFAAD/AQATAAcJShr0BQDWAQAuAAQKfysAAxIACQknJkIAAMsDABIACQnWJUIAAMsDABMACAmCInYNAJ4CAAAA.Gluggther:BAAALgAECgQJBAAAAA==.',
Go='Goru:BAAALgADCgYJBgAAAA==.',
Gr='Grahz:BAAALgAECgEJAQAAAA==.Gravyboat:BAAALgAECgYJEwAAAA==.Graydawn:BAAALgADCgcJCQAAAA==.Grimwillie:BAAALgAECgQJBgAAAA==.Grismago:BAAALgAFFAEJAQAAAA==.Grizzlebee:BAAALgADCgEJAQAAAA==.',
Gu='Gusto:BAAALgAECgQJBQAAAA==.',
['Gë']='Gënghiskhän:BAAALgADCgUJBQAAAA==.',
Ha='Haakon:BAAALgAECgEJAQAAAA==.Hammertaint:BAAALgADCgkJEQAAAA==.Harrowing:BAABLgAECn80AAIiAAkJICBxAgAtAwAiAAkJICBxAgAtAwAAAA==.Haurt:BAABLgAECn8qAAIXAAgJqhKlFQCRAQAXAAgJqhKlFQCRAQAAAA==.Havoq:BAAALgAECgMJAwAAAA==.',
He='Healamore:BAAALgADCgEJAgAAAA==.Healingway:BAAALgADCgUJBQABLgAECgYJCwAKAAAAAA==.Heavyhooves:BAABLgAECn8cAAIjAAcJjxDhHACCAQAjAAcJjxDhHACCAQAAAA==.Helawix:BAAALgADCgcJEAAAAA==.Hellful:BAABLgAECn8UAAMbAAkJBQq1KQB1AQAbAAkJBQq1KQB1AQAUAAMJxQEpfQBRAAAAAA==.Hellscrèam:BAAALgAECgMJBQAAAA==.Herc:BAAALgAECgEJAQAAAA==.',
Hi='Hischier:BAABLgAECn8gAAMkAAgJWxkjBwDkAQAkAAcJVBwjBwDkAQAPAAgJtgoSOwB7AQAAAA==.',
Ho='Holyjoey:BAAALgAECgYJDAAAAA==.Holymôley:BAABLgAECn8qAAIbAAkJliA0AwAeAwAbAAkJliA0AwAeAwAAAA==.Holytroller:BAAALgAECgUJCAAAAA==.Horrorcosmic:BAAALgADCgEJAQAAAA==.Hotbeeframen:BAAALgADCgEJAQAAAA==.',
Hu='Hulken:BAAALgADCgYJBgAAAA==.Humanpriest:BAAALgADCgEJAQABLgADCgkJCQAKAAAAAA==.Hussongs:BAAALgAECgEJAQAAAA==.',
['Hû']='Hûnta:BAAALgADCgQJBAAAAA==.',
Ic='Iceegoose:BAAALgAECgEJAQAAAA==.',
Ie='Ieratha:BAAALgAECgYJDwAAAA==.',
Il='Illidanina:BAAALgADCgUJBQABLgAFFAgJGwAkAMwmAA==.',
In='Insañe:BAAALgAECgkJAQAAAA==.Invi:BAABLgAECn8hAAMiAAkJAh5zEACPAgAiAAkJAh5zEACPAgAaAAcJwhXsfACAAQAAAA==.',
It='Itkøvian:BAAALgAECggJCAAAAA==.',
Ja='Jarrickah:BAAALgAECgQJBAAAAA==.Jaycito:BAAALgAECgYJCwAAAA==.Jayylols:BAAALgAECgcJBwAAAA==.',
Je='Jeor:BAABLgAECn8bAAIaAAYJ5wdOewD1AAAaAAYJ5wdOewD1AAAAAA==.Jereome:BAAALgAECgYJBgAAAA==.Jezhus:BAAALgADCgkJBgAAAA==.',
Ji='Jigsy:BAABLgAECn8gAAMPAAkJEyBnCAC/AgAPAAgJEyBnCAC/AgAVAAMJBx+ILAAMAQAAAA==.Jigy:BAAALgAECgYJDAAAAA==.Jimmy:BAAALgADCgcJBwAAAA==.',
Jo='Jokerzwild:BAAALgADCgQJBwAAAA==.Jorker:BAABLgAECn8bAAIDAAgJtR0OGgC4AgADAAgJtR0OGgC4AgAAAA==.Jovinistus:BAAALgADCgcJDwAAAA==.',
Ju='Judgecutìe:BAABLgAECn8aAAIiAAgJvRkuDgA1AgAiAAgJvRkuDgA1AgAAAA==.Jue:BAAALgAECgEJBQAAAA==.Juiice:BAAALgADCgcJBwAAAA==.',
['Jë']='Jësus:BAAALgAECgcJEAAAAA==.',
Ka='Kalandaelis:BAAALgADCgMJAwAAAA==.Kamisama:BAAALgAECgYJBwAAAA==.Kawalskie:BAAALgAECgQJBQAAAA==.Kazraghand:BAABLgAECn8tAAIlAAkJtQdtEQCYAQAlAAkJtQdtEQCYAQAAAA==.',
Ke='Kei:BAACLgAFFH8PAAIDAAQJxhMsIgAmAQADAAQJxhMsIgAmAQAuAAQKfywAAwMACAkoHZoLAHQCAAMACAkoHZoLAHQCAB4AAQkYDGFxADMAAAAA.Kelsio:BAABLgAECn8qAAICAAkJARAWHQDuAQACAAkJARAWHQDuAQAAAA==.Kess:BAAALgAECgcJEQAAAA==.Keyboardcatt:BAABLgAECn8XAAIaAAYJ8xvcQwB6AQAaAAYJ8xvcQwB6AQAAAA==.',
Kh='Kharos:BAABLgAECn8lAAMhAAgJXglvIQAfAQAYAAgJ0gWQOwBNAQAhAAgJZAdvIQAfAQAAAA==.',
Ki='Kikeo:BAAALgAECggJCgABLgAFFAQJDwADAMYTAA==.Killerwarz:BAAALgAECgEJAQAAAA==.Kirkoth:BAAALgAECgEJAQAAAA==.Kitariya:BAAALgADCgIJAgAAAA==.',
Kn='Knuts:BAABLgAECn8ZAAMVAAcJQAJjOwDGAAAVAAcJFQJjOwDGAAAPAAYJzwEl+ABpAAAAAA==.',
Ko='Kogori:BAAALgAECgUJCgAAAA==.Konsentrated:BAABLgAECn8ZAAIEAAYJZxaXXQBYAQAEAAYJZxaXXQBYAQAAAA==.Kowtagion:BAAALgADCgYJBgABLgAFFAQJDwAPAJ4YAA==.',
Ku='Kungfudegru:BAAALgAECggJCAAAAA==.Kuraven:BAAALgADCgcJBwAAAA==.Kuromo:BAAALgADCgMJBgAAAA==.',
Ky='Kylidan:BAAALgAECgEJAgAAAA==.Kyradin:BAAALgADCgIJAgABLgADCgYJDAAKAAAAAA==.Kyruutos:BAABLgAECn8XAAIaAAcJ9wWxiQDZAAAaAAcJ9wWxiQDZAAAAAA==.Kyvoker:BAAALgAECgQJBgAAAA==.',
['Kí']='Kítkat:BAABLgAECn8kAAIbAAgJ6xomFgBkAgAbAAgJ6xomFgBkAgAAAA==.',
La='Lachulax:BAAALgAECgQJBgAAAA==.Lacie:BAAALgAECgMJBwAAAA==.',
Le='Legato:BAAALgAECgEJAwAAAA==.Leibowitzy:BAABLgAECn8bAAIFAAYJthVNHgBCAQAFAAYJthVNHgBCAQAAAA==.Lettucee:BAAALgADCgYJBgAAAA==.Lexstrasza:BAAALgADCgEJAgAAAA==.',
Lh='Lhehitman:BAACLgAFFH8HAAIEAAQJRwwlMwBBAQAEAAQJRwwlMwBBAQAuAAQKfygAAwQACAmiIY03AJYCAAQACAmiIY03AJYCACAAAwmmEy0SAKEAAAAA.',
Li='Lifedeath:BAAALgADCgMJAwAAAA==.Lightsey:BAAALgAECgYJEAAAAA==.Lilth:BAAALgAECgEJAQABLgAECggJGgAiAL0ZAA==.Lindalamage:BAAALgADCgQJBQAAAA==.Linebreaker:BAAALgAECggJEwAAAA==.Litezamatch:BAAALgADCgIJAgAAAA==.Liveloveslay:BAAALgAECgkJBQAAAA==.',
Lo='Loreena:BAAALgADCgIJAgAAAA==.Lorein:BAAALgAECgQJBQAAAA==.',
Lu='Luckydog:BAAALgAECgQJCAABLgAECgYJDAAKAAAAAA==.Ludey:BAABLgAECn85AAMkAAkJfx2XAAC1AgAkAAkJfx2XAAC1AgAPAAEJeQR65wAtAAAAAA==.Lutnick:BAAALgAECgEJAQAAAA==.Lutray:BAABLgAECn8mAAIWAAgJ+yS+AQDnAgAWAAgJ+yS+AQDnAgAAAA==.',
Ly='Lysandriloc:BAABLgAECn8gAAQPAAgJOBACNgCNAQAPAAgJ5w0CNgCNAQAVAAUJlwUBOgDMAAAkAAMJERKvHACNAAAAAA==.',
Ma='Madcowdíseaz:BAABLgAECn8UAAIBAAgJdBTNLwC6AQABAAgJdBTNLwC6AQAAAA==.Madskadoosh:BAAALgADCgEJAQAAAA==.Madtotems:BAAALgAECgcJEgAAAA==.Magnator:BAAALgAFFAIJAgAAAA==.Malanore:BAABLgAECn8XAAIDAAcJ9hPMSgAYAQADAAcJ9hPMSgAYAQAAAA==.Manbeartree:BAAALgAECgIJAgABLgAFFAUJFQAiAFUhAA==.Manbeärpig:BAAALgAECgQJBwAAAA==.Maomao:BAABLgAECn8lAAIYAAkJ+xhZEABiAgAYAAkJ+xhZEABiAgAAAA==.Margherita:BAAALgADCgEJAQAAAA==.Marodd:BAABLgAECn8iAAIdAAgJyB4RCABKAgAdAAgJyB4RCABKAgAAAA==.Mashîra:BAABLgAFFH8HAAIlAAQJABVFBwBZAQAlAAQJABVFBwBZAQAAAA==.Matilda:BAAALgAECgEJAQAAAA==.Matylin:BAAALgADCgEJAQAAAA==.Maximus:BAACLgAFFH8FAAImAAMJ+R6NCQApAQAmAAMJ+R6NCQApAQAuAAQKfxkAAiYACQm5HygBAM4CACYACQm5HygBAM4CAAAA.',
Me='Meanmachine:BAAALgADCgIJAgAAAA==.Meatpocket:BAAALgAECgEJAgAAAA==.Meatwangs:BAABLgAECn8UAAIbAAYJTh6HIgChAQAbAAYJTh6HIgChAQAAAA==.Meleguar:BAAALgADCgIJBAAAAA==.Merihem:BAAALgADCggJDgAAAA==.Merpz:BAAALgADCgYJCwAAAA==.',
Mi='Mia:BAACLgAFFH8FAAIDAAQJ6xX8LgD1AAADAAQJ6xX8LgD1AAAuAAQKfxQAAgMABglHIJg6AAoCAAMABglHIJg6AAoCAAAA.Miamore:BAAALgADCgEJAQABLgADCgkJCQAKAAAAAA==.Milize:BAAALgAECgIJAgAAAA==.Milknkookies:BAAALgAECgIJAgAAAA==.Miney:BAAALgADCgkJEwAAAA==.Mirowen:BAAALgAECgYJBgABLgAECgUJBwAKAAAAAA==.Misc:BAAALgAECgcJCQAAAA==.Mistaeatit:BAABLgAECn8kAAIBAAcJ5iL3GAA2AgABAAcJ5iL3GAA2AgAAAA==.Mitch:BAAALgAECgQJCAAAAA==.Miu:BAAALgAECgUJBQAAAA==.',
Mk='Mkachen:BAAALgADCgUJBQAAAA==.',
Mo='Monkintrunk:BAAALgADCgIJAgAAAA==.Moody:BAAALgAECgEJAQAAAA==.Moondotter:BAAALgAECgYJEQAAAA==.Moonslayer:BAABLgAECn8WAAMXAAgJTB7DBgBwAgAXAAgJTB7DBgBwAgANAAEJiAFv6gAaAAAAAA==.Moovefool:BAABLgAECn8WAAMbAAcJyQg0OgAeAQAbAAcJyQg0OgAeAQAUAAMJiwIudgBpAAAAAA==.Mortimer:BAABLgAECn8kAAIBAAgJnRt+IQABAgABAAgJnRt+IQABAgAAAA==.',
Mu='Mudgeon:BAAALgAECgYJEQAAAA==.Mulheron:BAAALgADCgMJBAAAAA==.Mulletmonk:BAAALgAECgQJCAAAAA==.',
['Mâ']='Mâshîrâ:BAABLgAECn8dAAMUAAgJHSKiCgDsAgAUAAgJHSKiCgDsAgARAAMJwApEJACVAAABLgAFFAQJBwAlAAAVAA==.',
['Må']='Måshîrå:BAAALgAECgEJAQABLgAFFAQJBwAlAAAVAA==.',
Na='Nagarafan:BAABLgAECn8cAAIEAAcJfwv7XgBUAQAEAAcJfwv7XgBUAQAAAA==.Nakor:BAAALgAECgcJEgAAAA==.Natalie:BAAALgAECgQJCAAAAA==.',
Ne='Nefariat:BAAALgAECgMJBQAAAA==.Nefarious:BAAALgAECgEJAQABLgAECgMJBQAKAAAAAA==.Nefeli:BAABLgAECn8zAAMTAAkJ2BzuBAClAgATAAkJFhzuBAClAgASAAkJXBhCCgA6AgAAAA==.Nelinne:BAABLgAECn8iAAMlAAgJbAExKAC3AAAlAAgJYAExKAC3AAACAAMJDgFlygA7AAAAAA==.Nestia:BAAALgAECgQJCQAAAA==.Never:BAACLgAFFH8QAAIPAAUJ7iArEAB7AQAPAAUJ7iArEAB7AQAuAAQKfyoAAw8ACQmdJc0BALQDAA8ACQmdJc0BALQDABUABQnxIGoPANYBAAAA.',
Ni='Niccolò:BAAALgADCgEJAQAAAA==.Nidis:BAAALgADCgYJAQAAAA==.Nieve:BAAALgADCgEJAQAAAA==.Nightarrow:BAABLgAECn8nAAMCAAkJkxlDDQByAgACAAkJkxlDDQByAgAmAAEJKwBQnAAKAAAAAA==.Nightbird:BAAALgAECgkJAgAAAA==.Nightshade:BAABLgAECn81AAMCAAkJWx6aBgDIAgACAAkJWx6aBgDIAgAmAAgJQwtGOACDAQAAAA==.Nil:BAAALgAECgcJDQAAAA==.Ninjamonkggz:BAABLgAECn8UAAIJAAcJRxNhKgCKAQAJAAcJRxNhKgCKAQAAAA==.Nitron:BAAALgAECgcJBQAAAA==.Nix:BAABLgAECn8gAAIEAAgJ1RZvNgDIAQAEAAgJ1RZvNgDIAQAAAA==.',
No='Noanelororal:BAAALgAECgEJAQAAAA==.Nortney:BAABLgAECn8VAAIjAAgJ7hjhGgB1AgAjAAgJ7hjhGgB1AgAAAA==.Noskilzreq:BAAALgAECgQJCAAAAA==.Nostrum:BAAALgAECgYJCgAAAA==.Noughts:BAAALgADCgEJAQAAAA==.Novva:BAAALgAECgEJAQAAAA==.',
Nu='Nubootie:BAAALgAECgQJBAAAAA==.',
Ny='Nyckels:BAAALgADCgEJAQAAAA==.',
Oa='Oathbound:BAAALgADCgEJAQAAAA==.',
Ob='Oblaan:BAABLgAECn8lAAQPAAgJ/yAjDgB5AgAPAAcJoR8jDgB5AgAVAAUJSR2QFgCVAQAkAAEJHCKLJwBTAAAAAA==.',
Oc='Ocllo:BAABLgAECn8gAAInAAgJ9BLeFQBzAQAnAAgJ9BLeFQBzAQAAAA==.Octopusy:BAAALgAECgIJAgAAAA==.',
Oj='Ojo:BAABLgAECn8YAAIQAAgJwAzZCABEAQAQAAgJwAzZCABEAQAAAA==.',
On='Onebuttonaug:BAAALgAECgYJCwABLgAFFAcJGQAUAEoWAA==.Oniana:BAABLgAECn8pAAImAAgJUhTiBQDBAQAmAAgJUhTiBQDBAQAAAA==.',
Oo='Oozle:BAAALgADCgMJBQAAAA==.',
Op='Openwide:BAAALgADCgMJAwABLgAECgYJCwAKAAAAAA==.Oprahwinfuri:BAAALgADCgYJBgAAAA==.',
Or='Orccrusher:BAAALgADCgQJBwAAAA==.Orndushin:BAAALgADCgIJAgAAAA==.',
Ot='Ot:BAAALgAECgUJBwAAAA==.',
Pa='Pagamas:BAACLgAFFH8FAAIEAAMJ1RstPAAeAQAEAAMJ1RstPAAeAQAuAAQKfxsAAgQACAk/IiIwALICAAQACAk/IiIwALICAAAA.Painbringer:BAAALgAFFAMJAwAAAA==.Pajano:BAAALgADCgcJGQAAAA==.Palandari:BAAALgAECgEJAQAAAA==.Palawin:BAAALgADCgkJCQAAAA==.Pandawan:BAAALgADCgkJDAAAAA==.Panter:BAAALgAECgQJCwAAAA==.',
Pe='Peachpear:BAAALgAECgcJEQAAAA==.Perditious:BAAALgAECgQJBAAAAA==.',
Ph='Pharaoh:BAABLgAECn8uAAIdAAgJlRi8CwAIAgAdAAgJlRi8CwAIAgAAAA==.Phodoe:BAABLgAECn8gAAINAAgJnQ1BNwA6AQANAAgJnQ1BNwA6AQAAAA==.Phycara:BAAALgAECgMJBAAAAA==.Phyronix:BAAALgAECgQJBQAAAA==.',
Pi='Pickawp:BAAALgAECgQJBAAAAA==.Pikepole:BAAALgADCgkJCQAAAA==.',
Pl='Playne:BAABLgAECn8kAAIEAAgJOxu6HwAtAgAEAAgJOxu6HwAtAgAAAA==.',
Pn='Pnzr:BAAALgAECgcJCgAAAA==.',
Po='Pokeureyeout:BAABLgAECn8VAAICAAYJQQkrVQAPAQACAAYJQQkrVQAPAQAAAA==.Poofarts:BAAALgAECgEJAQAAAA==.Poostorclose:BAAALgAECgQJCQAAAA==.Pootonium:BAAALgAECgYJCgAAAA==.Popaul:BAAALgADCgYJCwAAAA==.',
Pr='Prahn:BAABLgAECn8iAAIbAAkJuA1RPQCMAQAbAAkJuA1RPQCMAQAAAA==.Preaced:BAABLgAECn8hAAIYAAgJYQ4fKwCcAQAYAAgJYQ4fKwCcAQAAAA==.Prokix:BAABLgAECn8ZAAIEAAgJNgdkagA8AQAEAAgJNgdkagA8AQAAAA==.Propainiac:BAAALgAECgQJBAAAAA==.',
Pu='Pumpkinpuff:BAABLgAECn8fAAIcAAgJJiLrAwDtAgAcAAgJJiLrAwDtAgAAAA==.',
['Pî']='Pîlot:BAAALgAECgYJDwABLgAECgYJEQAKAAAAAA==.',
Qu='Quiet:BAAALgAECgEJAQAAAA==.Quiettreader:BAABLgAECn8XAAIEAAYJnRcaYABSAQAEAAYJnRcaYABSAQAAAA==.Quokka:BAABLgAECn8ZAAMNAAYJSCQJDgBvAgANAAYJSCQJDgBvAgAXAAUJ5xc8NgBjAQAAAA==.',
Ra='Raambocatt:BAAALgAECgYJBgAAAA==.Raidboss:BAAALgAECgYJDAAAAA==.Raklem:BAABLgAECn8kAAMCAAkJeA/SIwDHAQACAAkJeA/SIwDHAQAmAAQJygNibQCJAAAAAA==.Rampage:BAAALgADCgYJBgABLgAECgYJGwAFALYVAA==.Ramssox:BAAALgAECgEJAQAAAA==.Raty:BAAALgAECgIJAgAAAA==.',
Re='Redeath:BAAALgAECgYJDwABLgAECggJKAAaALESAA==.Redirect:BAAALgAECgEJAQABLgAECggJKAAaALESAA==.Redonculous:BAAALgAECggJDQAAAA==.Redpool:BAAALgAECgMJBAAAAA==.Reinault:BAACLgAFFH8NAAIJAAQJCAtACwAeAQAJAAQJCAtACwAeAQAuAAQKfyUAAwkACQlDGsIVADwCAAkACQlDGsIVADwCABwABwnPCGI5AAMBAAAA.Reiramas:BAAALgAECgUJBQAAAA==.Relentful:BAAALgADCgIJAgAAAA==.Reliea:BAAALgAECgMJBAAAAA==.Renalla:BAAALgADCgYJBwAAAA==.Renix:BAAALgADCgcJCAAAAA==.Revansong:BAAALgAECgcJDgABLgAECggJKwAIAFojAA==.',
Ri='Rika:BAAALgADCgYJBgAAAA==.',
Ro='Ronx:BAABLgAECn8dAAIEAAgJNBWzOgC4AQAEAAgJNBWzOgC4AQAAAA==.Roodfrost:BAAALgADCgUJBwAAAA==.Roxxiloxxi:BAABLgAECn8kAAMPAAkJGwXFTgA9AQAPAAkJdgTFTgA9AQAVAAgJGgSzLgABAQAAAA==.Royal:BAABLgAECn8pAAIOAAgJDRXxCQB/AQAOAAgJDRXxCQB/AQAAAA==.',
Ru='Rudeboy:BAAALgAECgUJBgAAAA==.Ruination:BAAALgAECgEJBAAAAA==.Rukìa:BAAALgADCgUJBQABLgAFFAEJAQAKAAAAAA==.',
Sa='Sabria:BAACLgAFFH8FAAIiAAMJXAoSGwDMAAAiAAMJXAoSGwDMAAAuAAQKfzkAAyIACQn5GRQIAJMCACIACQn5GRQIAJMCABoACAnND9pcAMwBAAAA.Sahee:BAAALgADCgMJAwAAAA==.Sahria:BAAALgAECgYJDwAAAA==.Samlosco:BAABLgAECn8eAAISAAcJrBdoBACuAQASAAcJrBdoBACuAQAAAA==.Saninth:BAAALgAECgEJAQAAAA==.Sanwicheater:BAAALgAECgQJBAABLgAFFAMJBQAEANUbAA==.Satra:BAAALgADCggJCgAAAA==.Savus:BAAALgAECgYJCwAAAA==.',
Sc='Scalpelheals:BAACLgAFFH8cAAIhAAgJBxGBAQAnAgAhAAgJBxGBAQAnAgAuAAQKfzUABCEACQnCJb0AAKsDACEACQnCJb0AAKsDABgABwnvGvkbAP0BAB0AAQkeCRNiADQAAAAA.Sceledrus:BAAALgADCgcJDQAAAA==.Schizadin:BAAALgAECgcJBwAAAA==.Schizology:BAAALgADCgkJDAAAAA==.',
Se='Sebekuul:BAAALgAECggJCgAAAQ==.Selbur:BAAALgADCgMJAwABLgAFFAYJFQAJABMfAA==.Selfie:BAAALgADCgEJAgAAAA==.Sence:BAAALgAECgEJAQAAAA==.Sendy:BAAALgAECgYJCAAAAA==.Sephurik:BAACLgAFFH8UAAIEAAgJWhK4AgBaAgAEAAgJWhK4AgBaAgAuAAQKfzkAAgQACQm0I3YIAIMDAAQACQm0I3YIAIMDAAAA.Sepimoth:BAAALgADCgYJBgAAAA==.Septicaemia:BAAALgAECgMJAwAAAA==.Seriphan:BAAALgADCgQJBAAAAA==.Serovin:BAAALgADCgcJBwAAAA==.',
Sh='Shaolin:BAAALgADCgUJBQABLgAFFAEJAQAKAAAAAA==.Shawman:BAAALgADCgEJAQAAAA==.Sheepie:BAAALgADCgMJAwAAAA==.Shindorei:BAAALgAECgMJAwAAAA==.Shintai:BAAALgAECgUJDwAAAA==.Shnicklfritz:BAAALgADCgQJBQAAAA==.Showtek:BAABLgAECn8qAAMXAAgJxxmREQC9AQAOAAcJqhm1CgDrAQAXAAgJkxSREQC9AQAAAA==.Shyft:BAAALgAECgcJEAABLgAFFAEJAQAKAAAAAA==.Shyfted:BAAALgADCgUJBQABLgAFFAEJAQAKAAAAAA==.Shyfty:BAAALgAECgYJCAABLgAFFAEJAQAKAAAAAA==.Shîn:BAABLgAECn8aAAQaAAcJzxuVSwBjAQAaAAcJaxqVSwBjAQAnAAMJGQ0dMgCFAAAiAAIJXAWwigBTAAAAAA==.',
Si='Sickology:BAAALgAECgQJBgAAAA==.Sikanda:BAACLgAFFH8HAAIBAAMJNBURTQD1AAABAAMJNBURTQD1AAAuAAQKfx4AAgEACAmCI9ggAL4CAAEACAmCI9ggAL4CAAAA.Simplord:BAAALgAECgYJCQAAAA==.Sinara:BAAALgAECgUJCgAAAA==.Sintaxtwo:BAACLgAFFH8TAAMCAAUJISOyBQCOAQACAAUJISOyBQCOAQAmAAQJzhm0EwADAQAuAAQKfyAAAyYACQnoIy0IABwDACYACAnFIy0IABwDAAIAAgmsIkxvAMUAAAAA.Sion:BAABLgAECn8jAAIdAAgJyx9aBQCKAgAdAAgJyx9aBQCKAgAAAA==.Sithlordz:BAAALgAECgQJBgAAAA==.',
Sk='Sky:BAABLgAECn8XAAIEAAgJdCCGHwD2AgAEAAgJdCCGHwD2AgAAAA==.Skyelf:BAABLgAECn8hAAICAAgJOhCxLgD3AQACAAgJOhCxLgD3AQAAAA==.Skyrizzy:BAAALgAECgEJAQAAAA==.',
Sl='Sluggerr:BAABLgAECn8UAAIWAAgJXCCyCACUAgAWAAgJXCCyCACUAgAAAA==.',
Sm='Smallpox:BAAALgAECgQJBAAAAA==.Smitemedaddy:BAAALgADCgYJBQAAAA==.Smoke:BAAALgAECgMJAwAAAA==.Smokedeuce:BAAALgAECgIJAgABLgAECgMJAwAKAAAAAA==.Smokyette:BAAALgAECgMJAwAAAA==.',
So='Somira:BAAALgAECgQJBwAAAA==.Soraia:BAABLgAECn8UAAIEAAYJbAuoeAAfAQAEAAYJbAuoeAAfAQAAAA==.',
Sp='Spanktotank:BAAALgAECgYJDwAAAA==.Spectrecles:BAAALgAECgYJCwAAAA==.Spectrecless:BAAALgADCgQJBQABLgAECgYJCwAKAAAAAA==.Speez:BAABLgAECn8iAAMCAAgJdBNTJADEAQACAAgJdBNTJADEAQAmAAEJuQGbmgAYAAAAAA==.Spookieturbo:BAAALgAECgMJAwAAAA==.Spookyhunter:BAABLgAECn8OAAIDAAgJsiEJCAClAgADAAgJsiEJCAClAgAAAA==.',
St='Stablehand:BAABLgAECn8yAAICAAgJjRkhGAAPAgACAAgJjRkhGAAPAgAAAA==.Stephen:BAAALgADCgcJBwAAAA==.Steve:BAACLgAFFH8ZAAIUAAcJShZNAgDfAQAUAAcJShZNAgDfAQAuAAQKfyoAAhQACQkOIrQCAIIDABQACQkOIrQCAIIDAAAA.Stonedfel:BAABLgAECn8dAAIeAAkJuA78DgCSAQAeAAkJuA78DgCSAQAAAA==.Stonkbonkk:BAAALgAECgYJCwAAAA==.Stylez:BAAALgAECgYJCwAAAA==.',
Su='Sucsuck:BAAALgAECgMJAwAAAA==.Sundora:BAAALgAECggJEgAAAA==.Sunhoof:BAABLgAECn8cAAMnAAYJahj8FgBlAQAnAAYJtBb8FgBlAQAaAAYJqxQKYAAuAQAAAA==.Superuberbot:BAABLgAECn8bAAIdAAgJoRC9GwBeAQAdAAgJoRC9GwBeAQAAAA==.Superuberdot:BAABLgAECn8fAAQkAAYJvBY1EAArAQAkAAYJuhM1EAArAQAPAAQJGRWabwDrAAAVAAUJDAaDGgBuAAAAAA==.Superuberhot:BAAALgAECgQJBQAAAA==.Superubernot:BAAALgAECgEJAwAAAA==.',
Sy='Sylvyr:BAAALgAECgMJAwAAAA==.Syntacks:BAABLgAECn8hAAIEAAgJnBdjTQBOAgAEAAgJnBdjTQBOAgAAAA==.Syzara:BAAALgADCgYJCQAAAA==.',
['Sø']='Sørina:BAAALgAECgEJAQAAAA==.Sørrow:BAABLgAECn8eAAIDAAgJtg40PgA/AQADAAgJtg40PgA/AQAAAA==.',
Ta='Tabi:BAABLgAECn8jAAIEAAgJoQRjbgA0AQAEAAgJoQRjbgA0AQAAAA==.Tacts:BAAALgAECgYJDAAAAA==.Taiyn:BAAALgAECgQJBAABLgAECggJEwAKAAAAAA==.Takecare:BAAALgADCgIJAwAAAA==.Tankaa:BAAALgADCgYJBwAAAA==.',
Te='Terein:BAAALgADCgYJBwAAAA==.Test:BAAALgAECgcJDAAAAA==.',
Th='Thedawg:BAAALgADCgQJBAAAAA==.Thedayman:BAAALgAECgYJBgAAAA==.Theo:BAAALgAECgEJAQAAAA==.Therwinn:BAABLgAECn8eAAICAAgJGCJpDAB7AgACAAgJGCJpDAB7AgAAAA==.Thetaint:BAABLgAECn8mAAMIAAkJhSBKAgDYAgAIAAkJHCBKAgDYAgAQAAYJoRtTBgCJAQAAAA==.Thoradin:BAAALgADCgEJAQAAAA==.Thraxion:BAAALgAECgYJDwAAAA==.Thread:BAAALgAECgQJBgAAAA==.Threestorms:BAAALgADCgQJBAAAAA==.Thunderkow:BAAALgADCgcJCAABLgAFFAQJDwAPAJ4YAA==.Thunderous:BAAALgAECgQJBAAAAA==.',
Ti='Tinyrunes:BAAALgAECgYJEAAAAA==.',
To='Tojiguro:BAAALgADCgYJBwAAAA==.Tommoorello:BAAALgADCgEJAQAAAA==.Torags:BAAALgADCgEJAgAAAA==.Torrask:BAAALgADCgEJAQAAAA==.Totemofpeace:BAAALgAECgkJCwABLgAECggJIQAYAGEOAA==.Towfu:BAAALgAECggJEgAAAA==.',
Tr='Traelayn:BAAALgAECgEJAQAAAA==.Trapgawd:BAAALgADCgEJAQAAAA==.Trentlock:BAACLgAFFH8OAAIPAAQJFhEvKwAZAQAPAAQJFhEvKwAZAQAuAAQKfy4ABBUACAk/IEwJAEMBAA8ABwkGHo8vAKUBACQABAn/HL8GAEUBABUABQmaG0wJAEMBAAAA.Tristae:BAAALgAECgYJDQAAAA==.Trollslingin:BAAALgADCgkJEAAAAA==.Truuk:BAAALgAECgYJCAAAAA==.',
Ts='Tsu:BAAALgAECgEJAQAAAA==.',
Tu='Tunapie:BAAALgAECgEJAgAAAA==.',
Ty='Tyzula:BAAALgAECgcJCwAAAA==.',
['Tê']='Têstament:BAAALgAECgQJBAAAAA==.',
Ub='Ubasti:BAAALgAECgcJDgAAAA==.',
Un='Unstablesha:BAAALgAECgYJBgAAAA==.',
Ur='Urahara:BAAALgAECgQJBAAAAA==.',
Va='Valiriel:BAAALgADCgcJDQAAAA==.Varsalis:BAAALgADCgMJAwAAAA==.',
Ve='Velidra:BAAALgADCgYJCQAAAA==.Vellektra:BAAALgAECgEJAQAAAA==.Vernöm:BAAALgAECgQJBAAAAA==.Vethmoree:BAAALgAECgUJBwABLgAECggJGgAaAFgXAA==.',
Vi='Via:BAAALgAECgYJAwAAAA==.Vil:BAACLgAFFH8XAAIdAAgJNxmiAABxAgAdAAgJNxmiAABxAgAuAAQKfykAAh0ACQk7JtcCAHoDAB0ACQk7JtcCAHoDAAAA.Vilonus:BAABLgAECn8gAAIPAAgJDA5oNgCLAQAPAAgJDA5oNgCLAQAAAA==.Virvum:BAAALgAECgQJBAAAAA==.Vitiate:BAAALgAECgYJCAAAAA==.',
Vo='Voll:BAAALgAECgYJDgAAAA==.',
['Và']='Vàáko:BAAALgAECgIJAgAAAA==.',
Wa='Waxillium:BAAALgAECgcJCQAAAA==.',
We='Werebuddy:BAAALgADCgUJBQAAAA==.Weshyerga:BAAALgADCgYJBgABLgAFFAQJDgAFAL4kAA==.',
Wi='Wigly:BAABLgAECn8fAAIhAAgJ+A13EwCoAQAhAAgJ+A13EwCoAQAAAA==.Willathewise:BAAALgAECgYJBgAAAA==.Wingsolid:BAAALgADCgYJCwABLgAECgYJCwAKAAAAAA==.Withengar:BAABLgAECn8YAAIDAAgJ9B4sCwB5AgADAAgJ9B4sCwB5AgAAAA==.',
Wr='Wrathrine:BAAALgAECgQJCQAAAA==.',
Wu='Wuoshi:BAABLgAECn8UAAMcAAgJFRKxJgB9AQAcAAgJFRKxJgB9AQAJAAEJ/BAbWQA5AAAAAA==.Wuuzzyy:BAAALgAECgcJDwAAAA==.',
Xa='Xaliko:BAABLgAECn8hAAMPAAgJSyBICwCZAgAPAAgJSyBICwCZAgAVAAYJUxZIEgC6AQAAAA==.Xanathos:BAAALgADCgUJBQAAAA==.Xanbaran:BAABLgAECn85AAIYAAkJzgnQGwBsAQAYAAkJzgnQGwBsAQAAAA==.',
Xe='Xena:BAAALgAECgUJCAABLgAECggJKQAOAA0VAA==.Xero:BAAALgAECgMJAwABLgAECggJKQAOAA0VAA==.',
Xo='Xorellion:BAABLgAECn8mAAIEAAgJpg5RRQCXAQAEAAgJpg5RRQCXAQAAAA==.',
Xy='Xyrters:BAACLgAFFH8OAAILAAQJERHZDgAoAQALAAQJERHZDgAoAQAuAAQKfyAAAgsACAlPIWcEAA0DAAsACAlPIWcEAA0DAAAA.',
Ye='Yeji:BAAALgADCgEJAQAAAA==.',
Yi='Yiddiephokin:BAAALgADCgYJCAAAAA==.',
Yu='Yukigodx:BAAALgADCggJEQAAAA==.Yukki:BAAALgAECgcJBwAAAA==.',
Za='Zanus:BAAALgADCgEJAgAAAA==.Zapmommy:BAAALgADCgIJAgAAAA==.Zariel:BAAALgAECgQJCQAAAA==.Zartini:BAABLgAECn8TAAIDAAkJchehMwBnAQADAAkJchehMwBnAQAAAA==.Zaylas:BAAALgADCgMJAwAAAA==.',
Ze='Zeeba:BAAALgADCgEJAQAAAA==.Zerildk:BAABLgAECn8cAAIBAAgJ1RZtNwCcAQABAAgJ1RZtNwCcAQAAAA==.Zerphaine:BAABLgAECn8fAAINAAkJthL7GAD9AQANAAkJthL7GAD9AQAAAA==.Zevs:BAABLgAECn8VAAInAAgJdwu7GQBEAQAnAAgJdwu7GQBEAQAAAA==.',
Zi='Zic:BAABLgAECn8XAAIBAAcJcAwHVQA/AQABAAcJcAwHVQA/AQAAAA==.Zixxi:BAABLgAECn8rAAIEAAkJURvbEQCKAgAEAAkJURvbEQCKAgAAAA==.',
Zu='Zulakar:BAABLgAECn8cAAIiAAYJlhlKNgCjAQAiAAYJlhlKNgCjAQAAAA==.Zurxes:BAAALgAECgcJEAAAAA==.',
Zy='Zynatra:BAAALgAECgQJBwAAAA==.',
['Âk']='Âkaeus:BAABLgAECn8hAAIUAAkJuRPwEADYAQAUAAkJuRPwEADYAQAAAA==.',
['Ça']='Çaz:BAAALgADCgcJBwAAAA==.',
['Ëv']='Ëvø:BAAALgAECgQJCQAAAA==.',
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
