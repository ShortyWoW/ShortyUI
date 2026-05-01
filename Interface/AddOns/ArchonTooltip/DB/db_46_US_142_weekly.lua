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

local lookup = {'DeathKnight-Unholy','Hunter-BeastMastery','DemonHunter-Devourer','Mage-Frost','Warrior-Arms','DeathKnight-Blood','Rogue-Subtlety','Monk-Windwalker','Unknown-Unknown','Evoker-Preservation','DemonHunter-Vengeance','Druid-Restoration','Druid-Guardian','Warlock-Demonology','Shaman-Enhancement','Evoker-Devastation','Evoker-Augmentation','Shaman-Elemental','Warlock-Destruction','Warrior-Protection','Priest-Holy','Druid-Feral','Druid-Balance','Monk-Brewmaster','Paladin-Retribution','Shaman-Restoration','Priest-Shadow','DemonHunter-Havoc','Mage-Fire','Mage-Arcane','Priest-Discipline','Paladin-Holy','Warrior-Fury','Warlock-Affliction','Hunter-Survival','Hunter-Marksmanship','Paladin-Protection','Rogue-Assassination','Monk-Mistweaver',}
local provider = {region='US',realm="Lightning'sBlade",name='US',type='weekly',zone=46,date='2026-05-01',data={Ad='Aderai:BAAALgADCgYJCgAAAA==.',
Ae='Aeliong:BAAALgAECgEJAQAAAA==.Aendronys:BAAALgADCgQJAwAAAA==.',
Af='Afterparty:BAAALgAECggJEQAAAA==.',
Ag='Aguni:BAAALgAECgcJBwABLgAECggJHgABAIIjAA==.',
Ah='Ahmin:BAAALgADCgYJBgAAAA==.',
Ai='Aiura:BAAALgAECgQJBAAAAA==.',
Aj='Ajunlucky:BAACLgAFFH8JAAICAAMJ5BunFQASAQACAAMJ5BunFQASAQAuAAQKfycAAgIACAkOJCwQALkCAAIACAkOJCwQALkCAAAA.',
Al='Alagondar:BAAALgAECgYJEQAAAA==.Alakard:BAABLgAECn8PAAIDAAYJEhenMwAUAQADAAYJEhenMwAUAQAAAA==.Alberich:BAAALgAECgcJDwAAAA==.Alexari:BAAALgADCgcJCwAAAA==.Alexthejoker:BAAALgADCgQJAwAAAA==.Alody:BAAALgADCgMJAwAAAA==.Althenath:BAAALgADCgMJBAAAAA==.',
Am='Amalica:BAABLgAECn8WAAIEAAUJ7CAXRgBcAQAEAAUJ7CAXRgBcAQAAAA==.Amenadiel:BAAALgAECgcJCwAAAA==.Amuyal:BAAALgADCgYJBgAAAA==.',
An='Anaphylactic:BAAALgAECgYJBQAAAA==.Andrea:BAAALgAECgUJCgAAAA==.Angelline:BAAALgAECgUJCgABLgAFFAMJBwAFAMojAA==.Antimagi:BAAALgADCgkJCQAAAA==.',
Ap='Apheelia:BAAALgAECgQJCAAAAA==.Appypie:BAABLgAECn8bAAIGAAkJGQohDwAiAQAGAAkJGQohDwAiAQAAAA==.',
Ar='Arale:BAAALgAECgEJAQAAAA==.Aramala:BAAALgAECgIJAwAAAA==.Arkveld:BAABLgAECn8lAAIHAAgJOyIpAwB3AgAHAAgJOyIpAwB3AgAAAA==.',
As='Ashurasenku:BAAALgAECgkJCAAAAA==.Asten:BAAALgAECgMJAwAAAA==.',
At='Athair:BAABLgAECn8ZAAIIAAYJDh38DwB9AQAIAAYJDh38DwB9AQAAAA==.Athineana:BAAALgAECgQJBAAAAA==.',
Au='Augtistic:BAAALgAECgUJBQABLgAECgYJDgAJAAAAAA==.Aulken:BAAALgADCgEJAQAAAA==.',
Ay='Aylinn:BAABLgAECn8fAAIKAAgJ3hzmAgB7AgAKAAgJ3hzmAgB7AgAAAA==.Aylira:BAAALgAECgQJCAAAAA==.Aymonzo:BAABLgAECn8VAAMDAAYJYBfXWwCOAQADAAYJYBfXWwCOAQALAAEJ3g3pGQAqAAAAAA==.',
Az='Azem:BAAALgADCgkJDAAAAA==.',
Ba='Badlóck:BAAALgAECgcJBgAAAA==.Baharrar:BAACLgAFFH8HAAIMAAQJ1RiDCwBNAQAMAAQJ1RiDCwBNAQAuAAQKfx4AAwwACAkuI/UJAPUCAAwACAkuI/UJAPUCAA0AAQn0EtodADcAAAAA.Barofslovr:BAAALgADCgcJBwABLgAECgYJEQAJAAAAAA==.Barrylowmana:BAAALgADCgcJBwAAAA==.Bartendresse:BAAALgAECgEJAQAAAA==.Bastrasz:BAAALgAECgcJCwAAAA==.Batar:BAAALgADCgYJBgAAAA==.',
Be='Bearalas:BAACLgAFFH8NAAIOAAUJ9xSOGQA6AQAOAAUJ9xSOGQA6AQAuAAQKfxUAAg4ACQmpG/UYAL8CAA4ACQmpG/UYAL8CAAAA.Bearis:BAAALgADCgMJAwAAAA==.Beekin:BAAALgAECgUJCwAAAA==.Beeyah:BAABLgAECn8fAAICAAgJbh8kBwCEAgACAAgJbh8kBwCEAgAAAA==.Beldion:BAAALgADCgUJBQABLgAECgYJEwAJAAAAAA==.Bellator:BAAALgADCgMJAwAAAA==.Bellona:BAAALgADCgQJBAAAAA==.Bernarnold:BAAALgAECgYJEAAAAA==.Bettyspready:BAAALgAECgcJDQAAAA==.',
Bi='Bigoysters:BAAALgAECgMJAwAAAA==.Bigpoppapump:BAABLgAECn8ZAAIPAAYJISXrAgArAgAPAAYJISXrAgArAgAAAA==.Bigthumbb:BAAALgAECgEJAQAAAA==.Bikook:BAAALgADCgIJAgABLgAECggJGwAKACwQAA==.Binnyi:BAABLgAECn8kAAMQAAgJrA2jAwCoAQAQAAgJrA2jAwCoAQARAAYJogbpPAD6AAAAAA==.Biwwy:BAAALgAECgEJAQAAAA==.',
Bl='Blabidil:BAAALgADCgQJBAAAAA==.Blackfoot:BAABLgAECn8VAAISAAgJjBdxEAChAQASAAgJjBdxEAChAQAAAA==.Blackyeshua:BAACLgAFFH8GAAIRAAMJLAY4GwDMAAARAAMJLAY4GwDMAAAuAAQKfyYAAhEACAndGr4TAEYCABEACAndGr4TAEYCAAAA.Blastphemy:BAAALgADCgYJBgAAAA==.Blindpov:BAAALgADCggJCQAAAA==.',
Bo='Boanhead:BAAALgADCgIJAgAAAA==.Boomtiloom:BAAALgADCgMJAwAAAA==.Borgastraz:BAAALgAECgYJEAAAAA==.Boru:BAAALgADCgcJBwAAAA==.Boshin:BAAALgAECgEJAQAAAA==.Boshintime:BAAALgAECgMJAwAAAA==.Bouberry:BAABLgAECn8ZAAITAAYJbB/4AgDOAQATAAYJbB/4AgDOAQAAAA==.',
Br='Brewstoes:BAAALgADCgQJBQAAAA==.Bricksquadx:BAAALgAECgMJBQAAAA==.Brink:BAAALgADCgMJAwAAAA==.Broki:BAAALgAECgEJAQAAAA==.Brugnir:BAAALgAECgYJBgABLgAECgUJBwAJAAAAAA==.Bruwen:BAAALgADCgcJCAABLgAECgYJDgAJAAAAAA==.',
Bu='Bubblegruff:BAAALgADCgcJEAAAAA==.Bubbleohsevn:BAAALgAECgYJCQAAAA==.Bubblesaurus:BAABLgAECn8XAAMRAAYJcBbvHQARAQAQAAYJrA95IQAgAQARAAYJmxLvHQARAQAAAA==.Bum:BAAALgADCgkJCQAAAA==.Burlan:BAAALgAECgYJEgAAAA==.',
['Bé']='Béåst:BAAALgAECgYJDwAAAA==.',
['Bë']='Bërshton:BAAALgAECgYJCAAAAA==.',
Ca='Cakeshake:BAAALgAECgQJCQAAAA==.Caleris:BAABLgAECn8fAAIUAAgJaxdDBgDsAQAUAAgJaxdDBgDsAQAAAA==.Camelnuckle:BAABLgAECn8iAAISAAgJKhZqEAChAQASAAgJKhZqEAChAQAAAA==.Car:BAAALgADCgIJAgAAAA==.Cattle:BAAALgAECgcJDwAAAA==.',
Ch='Chaosglaive:BAAALgAECgcJEgAAAA==.Chaostorms:BAAALgAECgcJEgAAAA==.Chess:BAAALgAECgYJCwAAAA==.Chickenhydra:BAAALgADCgYJBgAAAA==.Chlorophil:BAAALgADCgYJBwAAAA==.Choochew:BAAALgAECgEJAgAAAA==.Chowlock:BAABLgAECn8fAAMTAAgJRSPaAgDTAgATAAcJmiPaAgDTAgAOAAQJFyJEawCMAQAAAA==.Chowmantwo:BAAALgADCgEJAQAAAA==.Chronical:BAAALgADCgcJBwAAAA==.',
Cl='Classicmonk:BAAALgAECgEJAQAAAA==.Clawsofpeace:BAAALgADCgkJDQABLgAECggJIQAVAGoOAA==.Cleverboi:BAAALgADCgYJBgAAAA==.',
Co='Constancia:BAAALgAECgUJDQAAAA==.',
Cr='Crackahjack:BAAALgAECgEJAQAAAA==.Craigor:BAAALgADCggJCQABLgAECggJEgAJAAAAAA==.Croppydust:BAAALgADCgcJDAAAAA==.Cryden:BAAALgADCgMJAwAAAA==.',
Cy='Cylicmylic:BAAALgAECgQJBAAAAA==.',
Cz='Czark:BAAALgAECgQJBAAAAA==.',
Da='Dalamaar:BAAALgADCgEJAQAAAA==.Dampundies:BAAALgAECgEJAQAAAA==.Dandey:BAAALgAECgYJBwAAAA==.Dangerdoom:BAAALgAECgIJAwABLgAECggJHQAEAJgXAA==.Dantee:BAABLgAECn8fAAILAAgJjx0JAgA2AgALAAgJjx0JAgA2AgAAAA==.Daps:BAAALgADCgcJCgAAAA==.Darkfoxgrime:BAABLgAECn8bAAIIAAkJHg36CgDFAQAIAAkJHg36CgDFAQAAAA==.Datsmywife:BAABLgAECn8ZAAMWAAcJTRCKEQCVAQAWAAcJTRCKEQCVAQAXAAUJYAX0LgCdAAAAAA==.Davis:BAAALgAECgcJBwABLgAECggJEwAJAAAAAA==.',
De='Deadvikingg:BAAALgAFFAIJAgAAAA==.Deadwix:BAAALgADCgIJAgAAAA==.Deebss:BAAALgAECgEJAQAAAA==.Degradation:BAAALgAECgEJBQAAAA==.Degru:BAAALgAECgYJDgAAAA==.Delaire:BAAALgAECgYJDwAAAA==.Demenhunta:BAAALgAECgMJAgAAAA==.Demonkow:BAACLgAFFH8LAAIOAAMJeSAcFwA3AQAOAAMJeSAcFwA3AQAuAAQKfyAAAw4ACAnuItgKAGECAA4ABwmmItgKAGECABMABAkPIgkbAHUBAAAA.Dereksama:BAAALgADCgQJBAAAAA==.Destrah:BAAALgADCgUJBQAAAA==.Deviiarrc:BAACLgAFFH8LAAIKAAMJZSMXCgAyAQAKAAMJZSMXCgAyAQAuAAQKfyQAAgoACAlLJSQDADUDAAoACAlLJSQDADUDAAAA.',
Di='Dikan:BAAALgADCgEJAQAAAA==.Dinosaurman:BAAALgAECgQJBAAAAA==.Disintegrate:BAAALgAECgcJBwABLgAECggJCgAJAAAAAA==.',
Do='Doova:BAAALgADCgYJCgAAAA==.Dorik:BAAALgADCgYJBgAAAA==.',
Dr='Dracar:BAAALgAECgYJEgAAAA==.Drackian:BAAALgAECgQJBAAAAA==.Dragondyne:BAAALgAECggJCAABLgAECgkJMAAYAGYaAA==.Drdurun:BAAALgADCgYJBwAAAA==.Drekavak:BAAALgAECgYJCAAAAA==.Drekfur:BAAALgADCgcJCgAAAA==.Drmmrfist:BAABLgAECn8qAAIYAAgJ5RWgCgDhAQAYAAgJ5RWgCgDhAQAAAA==.Druideca:BAAALgAECgYJDgAAAA==.',
Dw='Dwippietiggs:BAABLgAECn8qAAIZAAgJfCBjCACVAgAZAAgJfCBjCACVAgAAAA==.',
Ea='Earthfeather:BAAALgADCgIJAgAAAA==.',
Ec='Echoesonmute:BAAALgADCgEJAQAAAA==.',
Ed='Edhochuli:BAAALgADCgUJBQABLgAECgUJBQAJAAAAAA==.',
Ee='Eetee:BAABLgAECn8gAAQSAAgJ/hCGKwC7AQASAAgJ/hCGKwC7AQAPAAQJNQvFHwDVAAAaAAUJGw36PQC2AAAAAA==.',
Ek='Ekitten:BAAALgAECgYJCwAAAA==.',
El='Elandria:BAAALgAECgYJEAAAAA==.Elohym:BAAALgADCgUJBQAAAA==.Elsea:BAAALgAECgQJCQAAAA==.',
Em='Emberstone:BAAALgAECgEJAQAAAA==.Emotions:BAAALgAECgYJEgAAAA==.',
Ep='Epicdragon:BAAALgAECgMJBAAAAA==.',
Eq='Equesmortis:BAAALgAECgYJDgAAAA==.',
Er='Erös:BAAALgAECgUJDgAAAA==.',
Et='Etatoned:BAAALgAECgMJAwAAAA==.Etengaged:BAAALgAECgQJCAAAAA==.Ethavoc:BAAALgADCgQJBAAAAA==.',
Eu='Eurdice:BAAALgADCgIJAgAAAA==.',
Ev='Evo:BAAALgADCgUJBQAAAA==.Evrae:BAAALgAECgcJEQAAAA==.',
Ex='Extragrace:BAAALgAECgYJEQAAAA==.',
Fa='Faithshand:BAABLgAECn8kAAMVAAgJPgq5PQBDAQAVAAgJPgq5PQBDAQAbAAQJBAPDKwCiAAAAAA==.Fallenbow:BAAALgAECgUJBQAAAA==.Fappa:BAABLgAECn8mAAIOAAkJLg1fIQCuAQAOAAkJLg1fIQCuAQAAAA==.',
Fe='Featherstone:BAAALgADCgIJAwAAAA==.Feelzdope:BAAALgADCgQJBAAAAA==.Feio:BAABLgAECn8jAAIcAAgJgh9XAwBmAgAcAAgJgh9XAwBmAgAAAA==.Felfirez:BAAALgAECgEJAQAAAA==.Fellhock:BAAALgAECgMJAwAAAA==.Felydrak:BAABLgAECn8ZAAQQAAgJshSCDQABAgAQAAgJkhOCDQABAgAKAAMJfgaSGQBwAAARAAIJWgw2OgBoAAAAAA==.Fergilicious:BAAALgAECgYJEQAAAA==.',
Fi='Finkenator:BAACLgAFFH8VAAIEAAYJAhtJBQDaAQAEAAYJAhtJBQDaAQAuAAQKfyIAAgQACQl+I70KAG4DAAQACQl+I70KAG4DAAAA.Finkler:BAABLgAECn8rAAIEAAkJ6SIUBwDIAgAEAAkJ6SIUBwDIAgABLgAFFAYJFQAEAAIbAA==.Firedanny:BAAALgAECgUJCwAAAA==.',
Fl='Flameshock:BAABLgAECn8hAAQdAAgJcA8BBQB7AQAdAAcJfQoBBQB7AQAeAAQJAhDYBAAJAQAEAAQJdwOGJwGyAAAAAA==.Flippybippi:BAAALgAECgEJAQAAAA==.Flixur:BAACLgAFFH8HAAIEAAMJYxQKMgAFAQAEAAMJYxQKMgAFAQAuAAQKfx8AAgQABwnkH70ZABECAAQABwnkH70ZABECAAAA.Flyzikman:BAAALgADCgEJAQAAAA==.',
Fo='Forté:BAAALgADCgMJAwAAAA==.',
Fr='Freek:BAAALgAECgEJAgABLgAECgUJBgAJAAAAAA==.Freewillie:BAAALgAECgEJAgABLgAECgQJBgAJAAAAAA==.Friarmj:BAABLgAECn8rAAIfAAgJUg5UDADFAQAfAAgJUg5UDADFAQAAAA==.Frigidbeach:BAAALgAECgYJEAAAAA==.Frozeny:BAAALgADCgcJDQAAAA==.',
Fu='Furrita:BAAALgADCgcJBwAAAA==.',
Ga='Gainesta:BAAALgAECgYJEQAAAA==.Galazeth:BAAALgAECgcJDQABLgAECggJHgABAIIjAA==.Gamthor:BAAALgAECggJEgAAAA==.',
Ge='Germz:BAAALgAECgkJBwAAAA==.',
Gi='Gildeddash:BAAALgAECgYJDwAAAA==.Giudice:BAAALgADCgkJDAAAAA==.',
Gl='Glengoyne:BAAALgAECgQJDAAAAA==.Globoe:BAACLgAFFH8bAAMQAAgJeR5GAAD/AQAQAAUJeyRGAAD/AQARAAcJUBoCAwDgAQAuAAQKfysAAxAACQknJkIAAMsDABAACQnWJUIAAMsDABEACAmCInkNAJ4CAAAA.Gluggther:BAAALgADCgkJDAAAAA==.',
Go='Goru:BAAALgADCgYJBgAAAA==.',
Gr='Grahz:BAAALgAECgEJAQAAAA==.Gravyboat:BAAALgAECgYJEwAAAA==.Graydawn:BAAALgADCgcJCQAAAA==.Grimwillie:BAAALgAECgQJBgAAAA==.Grismago:BAAALgAFFAEJAQAAAA==.Grizzlebee:BAAALgADCgEJAQAAAA==.',
Gu='Gusto:BAAALgAECgIJAwAAAA==.',
['Gë']='Gënghiskhän:BAAALgADCgUJBQAAAA==.',
Ha='Haakon:BAAALgAECgEJAQAAAA==.Hammertaint:BAAALgADCggJCAAAAA==.Harrowing:BAABLgAECn8sAAIgAAkJQx85AgD9AgAgAAkJQx85AgD9AgAAAA==.Haurt:BAABLgAECn8iAAIXAAgJVhJbEACQAQAXAAgJVhJbEACQAQAAAA==.Havoq:BAAALgAECgMJAwAAAA==.',
He='Healamore:BAAALgADCgEJAgAAAA==.Healingway:BAAALgADCgUJBQABLgAECgUJBQAJAAAAAA==.Heavyhooves:BAABLgAECn8VAAIhAAYJQQp7IwAdAQAhAAYJQQp7IwAdAQAAAA==.Helawix:BAAALgADCgQJBAAAAA==.Hellful:BAAALgAECgcJCQAAAA==.Hellscrèam:BAAALgAECgMJBQAAAA==.Herc:BAAALgAECgEJAQAAAA==.',
Hi='Hischier:BAABLgAECn8dAAMiAAgJXRkjBwDkAQAiAAcJWRwjBwDkAQAOAAcJjgpZNwBOAQAAAA==.',
Ho='Holyjoey:BAAALgAECgYJCwAAAA==.Holymôley:BAABLgAECn8hAAIaAAgJUSKtAwDPAgAaAAgJUSKtAwDPAgAAAA==.Holytroller:BAAALgAECgUJCAAAAA==.Horrorcosmic:BAAALgADCgEJAQAAAA==.Hotbeeframen:BAAALgADCgEJAQAAAA==.',
Hu='Hulken:BAAALgADCgYJBgAAAA==.Humanpriest:BAAALgADCgEJAQABLgADCgkJCQAJAAAAAA==.Hussongs:BAAALgAECgEJAQAAAA==.',
['Hû']='Hûnta:BAAALgADCgQJBAAAAA==.',
Ic='Iceegoose:BAAALgAECgEJAQAAAA==.',
Ie='Ieratha:BAAALgAECgUJCQAAAA==.',
Il='Illidanina:BAAALgADCgUJBQABLgAFFAcJFAAiAG8lAA==.',
In='Invi:BAABLgAECn8dAAMgAAgJ1R5yEACPAgAgAAgJ1R5yEACPAgAZAAYJpRTqfACAAQAAAA==.',
It='Itkøvian:BAAALgAECggJCAAAAA==.',
Ja='Jarrickah:BAAALgAECgQJBAAAAA==.Jaycito:BAAALgAECgYJCwAAAA==.Jayylols:BAAALgAECgYJBgAAAA==.',
Je='Jeor:BAAALgAECgUJEgAAAA==.Jezhus:BAAALgADCgkJBgAAAA==.',
Ji='Jigsy:BAABLgAECn8gAAMOAAkJECCkBADQAgAOAAgJECCkBADQAgATAAMJBx+HLAAMAQAAAA==.Jigy:BAAALgAECgYJDAAAAA==.Jimmy:BAAALgADCgcJBwAAAA==.',
Jo='Jokerzwild:BAAALgADCgQJBwAAAA==.Jorker:BAABLgAECn8YAAIDAAgJtR0RGgC3AgADAAgJtR0RGgC3AgAAAA==.Jovinistus:BAAALgADCgcJDwAAAA==.',
Ju='Judgecutìe:BAAALgAECgcJEgAAAA==.Jue:BAAALgAECgEJBQAAAA==.Juiice:BAAALgADCgcJBwAAAA==.',
['Jë']='Jësus:BAAALgAECgcJEAAAAA==.',
Ka='Kamisama:BAAALgAECgEJAQAAAA==.Kawalskie:BAAALgAECgQJBQAAAA==.Kazraghand:BAABLgAECn8qAAIjAAgJOQh+DwBnAQAjAAgJOQh+DwBnAQAAAA==.',
Ke='Kei:BAACLgAFFH8MAAIDAAQJBRLgFQAgAQADAAQJBRLgFQAgAQAuAAQKfygAAwMACAnSHSYGAHoCAAMACAnSHSYGAHoCABwAAQkYDGJxADMAAAAA.Kelsio:BAABLgAECn8hAAICAAgJ9A6MIACeAQACAAgJ9A6MIACeAQAAAA==.Kess:BAAALgAECgYJDQAAAA==.Keyboardcatt:BAABLgAECn8XAAIZAAYJ8hsQLwCFAQAZAAYJ8hsQLwCFAQAAAA==.',
Kh='Kharos:BAABLgAECn8lAAMfAAgJWQlpGAAnAQAVAAgJ0gWJOwBNAQAfAAgJXwdpGAAnAQAAAA==.',
Ki='Kikeo:BAAALgAECggJCQABLgAFFAQJDAADAAUSAA==.Killerwarz:BAAALgAECgEJAQAAAA==.Kirkoth:BAAALgADCgkJGgAAAA==.Kitariya:BAAALgADCgIJAgAAAA==.',
Kn='Knuts:BAABLgAECn8ZAAMTAAcJPQJmOwDGAAATAAcJFQJmOwDGAAAOAAYJzAEX+ABpAAAAAA==.',
Ko='Kogori:BAAALgAECgUJCgAAAA==.Konsentrated:BAAALgAECgYJEwAAAA==.Kowtagion:BAAALgADCgYJBgABLgAFFAQJCwAOAHkgAA==.',
Ku='Kuraven:BAAALgADCgcJBwAAAA==.Kuromo:BAAALgADCgMJBgAAAA==.',
Ky='Kylidan:BAAALgAECgEJAgAAAA==.Kyradin:BAAALgADCgIJAgABLgADCgYJDAAJAAAAAA==.Kyruutos:BAABLgAECn8WAAIZAAYJ6ga3cADNAAAZAAYJ6ga3cADNAAAAAA==.Kyvoker:BAAALgAECgQJBgAAAA==.',
['Kí']='Kítkat:BAABLgAECn8kAAIaAAgJ7BoqDAAoAgAaAAgJ7BoqDAAoAgAAAA==.',
La='Lachulax:BAAALgAECgIJAgAAAA==.Lacie:BAAALgAECgMJBwAAAA==.',
Le='Legato:BAAALgAECgEJAwAAAA==.Leibowitzy:BAAALgAECgYJEwAAAA==.Lettucee:BAAALgADCgYJBgAAAA==.Lexstrasza:BAAALgADCgEJAgAAAA==.',
Lh='Lhehitman:BAABLgAECn8lAAMEAAgJuiCUNwCWAgAEAAgJuiCUNwCWAgAeAAMJphMvEgChAAAAAA==.',
Li='Lifedeath:BAAALgADCgMJAwAAAA==.Lightsey:BAAALgAECgYJCwAAAA==.Lilth:BAAALgAECgEJAQABLgAECgcJEgAJAAAAAA==.Lindalamage:BAAALgADCgQJBQAAAA==.Linebreaker:BAAALgAECggJEQAAAA==.Litezamatch:BAAALgADCgIJAgAAAA==.Liveloveslay:BAAALgAECgkJBQAAAA==.',
Lo='Loreena:BAAALgADCgIJAgAAAA==.Lorein:BAAALgAECgQJBQAAAA==.',
Lu='Luckydog:BAAALgAECgQJBwAAAA==.Ludey:BAABLgAECn8wAAMiAAkJ1xdyAACEAgAiAAkJ1xdyAACEAgAOAAEJYAQqvAAtAAAAAA==.Lutnick:BAAALgAECgEJAQAAAA==.Lutray:BAABLgAECn8kAAIUAAgJvST4AADoAgAUAAgJvST4AADoAgAAAA==.',
Ly='Lysandriloc:BAABLgAECn8gAAQOAAgJNhA+JgCWAQAOAAgJ4A0+JgCWAQATAAUJlwUCOgDMAAAiAAMJEBKtHACNAAAAAA==.',
Ma='Madcowdíseaz:BAABLgAECn8UAAIBAAgJcxTxHwDIAQABAAgJcxTxHwDIAQAAAA==.Madskadoosh:BAAALgADCgEJAQAAAA==.Madtotems:BAAALgAECgcJEgAAAA==.Magnator:BAAALgAECgMJAwAAAA==.Malanore:BAABLgAECn8XAAIDAAcJ0hMTMgAaAQADAAcJ0hMTMgAaAQAAAA==.Manbeartree:BAAALgAECgIJAgABLgAFFAUJEAAgACsbAA==.Manbeärpig:BAAALgAECgQJBwAAAA==.Maomao:BAABLgAECn8hAAIVAAgJShtbEABiAgAVAAgJShtbEABiAgAAAA==.Marodd:BAABLgAECn8iAAIbAAgJyh7WBABUAgAbAAgJyh7WBABUAgAAAA==.Mashîra:BAAALgAFFAIJAwAAAA==.Matilda:BAAALgAECgEJAQAAAA==.Matylin:BAAALgADCgEJAQAAAA==.Maximus:BAABLgAECn8VAAIkAAgJthzCAQBXAgAkAAgJthzCAQBXAgAAAA==.',
Me='Meanmachine:BAAALgADCgIJAgAAAA==.Meatpocket:BAAALgAECgEJAQAAAA==.Meatwangs:BAAALgAECgYJDwAAAA==.Meleguar:BAAALgADCgIJBAAAAA==.Merihem:BAAALgADCggJDgAAAA==.Merpz:BAAALgADCgYJCwAAAA==.',
Mi='Mia:BAACLgAFFH8FAAIDAAQJ6hVzHAD7AAADAAQJ6hVzHAD7AAAuAAQKfxQAAgMABgnJH6Q6AAoCAAMABgnJH6Q6AAoCAAAA.Miamore:BAAALgADCgEJAQABLgADCgkJCQAJAAAAAA==.Milize:BAAALgAECgIJAgAAAA==.Milknkookies:BAAALgAECgIJAgAAAA==.Miney:BAAALgADCgkJEQAAAA==.Mirowen:BAAALgAECgYJBgABLgAECgUJBwAJAAAAAA==.Misc:BAAALgAECgYJBwAAAA==.Mistaeatit:BAABLgAECn8dAAIBAAcJ5yLjFgADAgABAAcJ5yLjFgADAgAAAA==.Mitch:BAAALgAECgQJCAAAAA==.Miu:BAAALgAECgQJBAAAAA==.',
Mk='Mkachen:BAAALgADCgUJBQAAAA==.',
Mo='Monkintrunk:BAAALgADCgIJAgAAAA==.Moody:BAAALgAECgEJAQAAAA==.Moondotter:BAAALgAECgUJCwAAAA==.Moonslayer:BAABLgAECn8UAAMXAAgJaxq3BgAwAgAXAAgJaxq3BgAwAgAMAAEJiAFo6gAaAAAAAA==.Moovefool:BAAALgAECgYJDwAAAA==.Mortimer:BAABLgAECn8kAAIBAAgJnBs0FAAYAgABAAgJnBs0FAAYAgAAAA==.',
Mu='Mudgeon:BAAALgAECgYJEQAAAA==.Mulheron:BAAALgADCgMJBAAAAA==.Mulletmonk:BAAALgAECgQJCAAAAA==.',
['Mâ']='Mâshîrâ:BAABLgAECn8dAAMSAAgJHSKhCgDsAgASAAgJHSKhCgDsAgAPAAMJwApCJACVAAABLgAFFAIJAwAJAAAAAA==.',
['Må']='Måshîrå:BAAALgAECgEJAQABLgAFFAIJAwAJAAAAAA==.',
Na='Nagarafan:BAABLgAECn8WAAIEAAYJ7Ak/cwDyAAAEAAYJ7Ak/cwDyAAAAAA==.Nakor:BAAALgAECgcJEgAAAA==.Natalie:BAAALgAECgQJBgAAAA==.',
Ne='Nefariat:BAAALgAECgMJBQAAAA==.Nefarious:BAAALgAECgEJAQABLgAECgMJBQAJAAAAAA==.Nefeli:BAABLgAECn8qAAMRAAkJXBgHCgDqAQAQAAkJXBg/CgA6AgARAAkJDA8HCgDqAQAAAA==.Nelinne:BAABLgAECn8fAAMjAAgJQwE2HwCrAAAjAAgJNwE2HwCrAAACAAMJDgFgygA7AAAAAA==.Nestia:BAAALgAECgQJCQAAAA==.Never:BAACLgAFFH8LAAIOAAQJjB9QCgCAAQAOAAQJjB9QCgCAAQAuAAQKfycAAw4ACQmdJc0BALQDAA4ACQmdJc0BALQDABMABQnxIGkPANYBAAAA.',
Ni='Niccolò:BAAALgADCgEJAQAAAA==.Nidis:BAAALgADCgYJAQAAAA==.Nieve:BAAALgADCgEJAQAAAA==.Nightarrow:BAABLgAECn8hAAMCAAgJ+xbrEwDzAQACAAgJ+xbrEwDzAQAkAAEJKwBEnAAKAAAAAA==.Nightbird:BAAALgAECgkJAQAAAA==.Nightshade:BAABLgAECn8sAAMCAAkJwxzQAwDJAgACAAkJwxzQAwDJAgAkAAgJQwv+OAB9AQAAAA==.Nil:BAAALgAECgcJCwAAAA==.Ninjamonkggz:BAABLgAECn8UAAIIAAcJRxNnKgCKAQAIAAcJRxNnKgCKAQAAAA==.Nitron:BAAALgAECgcJAgAAAA==.Nix:BAABLgAECn8eAAIEAAgJZhVhLQCuAQAEAAgJZhVhLQCuAQAAAA==.',
No='Noanelororal:BAAALgAECgEJAQAAAA==.Nortney:BAABLgAECn8VAAIhAAgJ7RjkGgB1AgAhAAgJ7RjkGgB1AgAAAA==.Noskilzreq:BAAALgAECgQJCAAAAA==.Nostrum:BAAALgAECgYJCgAAAA==.Noughts:BAAALgADCgEJAQAAAA==.Novva:BAAALgAECgEJAQAAAA==.',
Nu='Nubootie:BAAALgAECgQJBAAAAA==.',
Ny='Nyckels:BAAALgADCgEJAQAAAA==.',
Oa='Oathbound:BAAALgADCgEJAQAAAA==.',
Ob='Oblaan:BAABLgAECn8jAAQOAAgJaSDMCQBwAgAOAAcJCh/MCQBwAgATAAUJSR2QFgCVAQAiAAEJHCKMJwBTAAAAAA==.',
Oc='Ocllo:BAABLgAECn8eAAIlAAgJQRLcFQBzAQAlAAgJQRLcFQBzAQAAAA==.',
Oj='Ojo:BAABLgAECn8YAAImAAgJwQx+BgBKAQAmAAgJwQx+BgBKAQAAAA==.',
On='Onebuttonaug:BAAALgAECgYJCwABLgAFFAcJGQASAFIWAA==.Oniana:BAABLgAECn8hAAIkAAcJnAzTCQA2AQAkAAcJnAzTCQA2AQAAAA==.',
Oo='Oozle:BAAALgADCgEJAgAAAA==.',
Op='Openwide:BAAALgADCgMJAwABLgAECgUJBQAJAAAAAA==.Oprahwinfuri:BAAALgADCgYJBgAAAA==.',
Or='Orccrusher:BAAALgADCgQJBwAAAA==.Orndushin:BAAALgADCgIJAgAAAA==.',
Ot='Ot:BAAALgAECgUJBgAAAA==.',
Pa='Pagamas:BAABLgAECn8bAAIEAAgJPyIiMACyAgAEAAgJPyIiMACyAgAAAA==.Painbringer:BAAALgAFFAMJAwAAAA==.Pajano:BAAALgADCgcJGQAAAA==.Palandari:BAAALgAECgEJAQAAAA==.Palawin:BAAALgADCgkJCQAAAA==.Pandawan:BAAALgADCgkJDAAAAA==.Panter:BAAALgAECgQJCgAAAA==.',
Pe='Peachpear:BAAALgAECgcJEQAAAA==.Perditious:BAAALgAECgQJBAAAAA==.',
Ph='Pharaoh:BAABLgAECn8iAAIbAAgJKRagCgDWAQAbAAgJKRagCgDWAQAAAA==.Phodoe:BAABLgAECn8eAAIMAAgJGQzuLgAiAQAMAAgJGQzuLgAiAQAAAA==.Phycara:BAAALgAECgMJAwAAAA==.Phyronix:BAAALgAECgEJAQAAAA==.',
Pi='Pickawp:BAAALgAECgQJBAAAAA==.Pikepole:BAAALgADCgkJCQAAAA==.',
Pl='Playne:BAABLgAECn8iAAIEAAgJghr2GAAWAgAEAAgJghr2GAAWAgAAAA==.',
Pn='Pnzr:BAAALgAECgcJCgAAAA==.',
Po='Pokeureyeout:BAAALgAECgUJCgAAAA==.Poofarts:BAAALgAECgEJAQAAAA==.Poostorclose:BAAALgAECgQJCQAAAA==.Pootonium:BAAALgAECgYJCgAAAA==.Popaul:BAAALgADCgYJCwAAAA==.',
Pr='Prahn:BAABLgAECn8iAAIaAAkJvg1SPQCMAQAaAAkJvg1SPQCMAQAAAA==.Preaced:BAABLgAECn8hAAIVAAgJag4BFAB0AQAVAAgJag4BFAB0AQAAAA==.Prokix:BAAALgAECgYJEQAAAA==.Propainiac:BAAALgAECgQJBAAAAA==.',
Pu='Pumpkinpuff:BAABLgAECn8cAAInAAYJOiKXCAAqAgAnAAYJOiKXCAAqAgAAAA==.',
['Pî']='Pîlot:BAAALgAECgQJBAABLgAECgYJEQAJAAAAAA==.',
Qu='Quiet:BAAALgAECgEJAQAAAA==.Quiettreader:BAAALgAECgUJDwAAAA==.Quokka:BAABLgAECn8WAAMMAAYJoSMXCgBoAgAMAAYJoSMXCgBoAgAXAAUJ5xc2NgBjAQAAAA==.',
Ra='Raambocatt:BAAALgADCgUJBQAAAA==.Raidboss:BAAALgAECgYJDAAAAA==.Raklem:BAABLgAECn8hAAMCAAgJmhARIQCbAQACAAgJmhARIQCbAQAkAAQJygNSbQCJAAAAAA==.Rampage:BAAALgADCgYJBgABLgAECgYJEwAJAAAAAA==.Ramssox:BAAALgAECgEJAQAAAA==.Raty:BAAALgAECgIJAgAAAA==.',
Re='Redeath:BAAALgAECgQJCQABLgAECgUJBQAJAAAAAA==.Redirect:BAAALgAECgEJAQABLgAECgUJBQAJAAAAAA==.Redonculous:BAAALgAECggJDQAAAA==.Redpool:BAAALgAECgEJAQAAAA==.Reinault:BAACLgAFFH8JAAIIAAMJjQyxCwDmAAAIAAMJjQyxCwDmAAAuAAQKfyAAAwgACAlzG8QVADwCAAgACAlzG8QVADwCACcABwnPCGE5AAMBAAAA.Reiramas:BAAALgAECgUJBQAAAA==.Relentful:BAAALgADCgIJAgAAAA==.Reliea:BAAALgAECgMJBAAAAA==.Renalla:BAAALgADCgYJBwAAAA==.Renix:BAAALgADCgcJBwAAAA==.Revansong:BAAALgAECgcJCwABLgAECggJJQAHADsiAA==.',
Ri='Rika:BAAALgADCgYJBgAAAA==.',
Ro='Ronx:BAABLgAECn8aAAIEAAgJMhXGKQC9AQAEAAgJMhXGKQC9AQAAAA==.Roodfrost:BAAALgADCgUJBwAAAA==.Roxxiloxxi:BAABLgAECn8dAAMTAAgJpAS0LgABAQATAAgJFwS0LgABAQAOAAYJoAM9WADoAAAAAA==.Royal:BAABLgAECn8pAAINAAgJDRUGBwCBAQANAAgJDRUGBwCBAQAAAA==.',
Ru='Rudeboy:BAAALgAECgUJBgAAAA==.Ruination:BAAALgAECgEJBAAAAA==.Rukìa:BAAALgADCgUJBQABLgAECgYJDgAJAAAAAA==.',
Sa='Sabria:BAABLgAECn8wAAMgAAkJ/hkkBAC5AgAgAAkJ/hkkBAC5AgAZAAgJ1A7aXADMAQAAAA==.Sahee:BAAALgADCgMJAwAAAA==.Sahria:BAAALgAECgYJCwAAAA==.Samlosco:BAABLgAECn8YAAIQAAcJqhUxBQBgAQAQAAcJqhUxBQBgAQAAAA==.Saninth:BAAALgAECgEJAQAAAA==.Satra:BAAALgADCggJCgAAAA==.Savus:BAAALgAECgQJBAAAAA==.',
Sc='Scalpelheals:BAACLgAFFH8cAAIfAAgJDBGAAQAnAgAfAAgJDBGAAQAnAgAuAAQKfzUABB8ACQnAJb0AAKsDAB8ACQnAJb0AAKsDABUABwnvGvgbAP0BABsAAQkeCRRiADQAAAAA.Sceledrus:BAAALgADCgcJDQAAAA==.Schizadin:BAAALgAECgYJBgAAAA==.Schizology:BAAALgADCgkJDAAAAA==.',
Se='Sebekuul:BAAALgAECggJCgAAAQ==.Selbur:BAAALgADCgMJAwAAAA==.Selfie:BAAALgADCgEJAgAAAA==.Sence:BAAALgAECgEJAQAAAA==.Sendy:BAAALgAECgYJCAAAAA==.Sephurik:BAACLgAFFH8UAAIEAAgJNxK2AgBaAgAEAAgJNxK2AgBaAgAuAAQKfzUAAgQACQm0I3gIAIMDAAQACQm0I3gIAIMDAAAA.Sepimoth:BAAALgADCgYJBgAAAA==.Septicaemia:BAAALgAECgMJAwAAAA==.Seriphan:BAAALgADCgQJBAAAAA==.Serovin:BAAALgADCgcJBwAAAA==.',
Sh='Shaolin:BAAALgADCgUJBQABLgAECgYJDgAJAAAAAA==.Sheepie:BAAALgADCgMJAwAAAA==.Shindorei:BAAALgAECgMJAwAAAA==.Shintai:BAAALgAECgUJDwAAAA==.Shnicklfritz:BAAALgADCgQJBQAAAA==.Showtek:BAABLgAECn8kAAMNAAgJexm1CgDrAQANAAcJqxm1CgDrAQAXAAgJvQ6TEgB2AQAAAA==.Shyft:BAAALgAECgYJDgAAAA==.Shyfted:BAAALgADCgUJBQABLgAECgYJDgAJAAAAAA==.Shyfty:BAAALgAECgYJCAABLgAECgYJDgAJAAAAAA==.Shîn:BAABLgAECn8aAAQZAAcJxxsaNgBrAQAZAAcJYxoaNgBrAQAlAAMJGQ0gMgCFAAAgAAIJXAWiigBTAAAAAA==.',
Si='Sickology:BAAALgAECgQJBgAAAA==.Sikanda:BAABLgAECn8eAAIBAAgJgiPaIAC+AgABAAgJgiPaIAC+AgAAAA==.Simplord:BAAALgAECgYJCQAAAA==.Sinara:BAAALgAECgUJCgAAAA==.Sintaxtwo:BAACLgAFFH8OAAMCAAUJZSG2AwCHAQACAAUJYx+2AwCHAQAkAAMJzhmvEwADAQAuAAQKfyAAAyQACQnoIyMIABoDACQACAnFIyMIABoDAAIAAgmtIs9UAMwAAAAA.Sion:BAABLgAECn8fAAIbAAgJxB89AwCLAgAbAAgJxB89AwCLAgAAAA==.Sithlordz:BAAALgAECgQJBgAAAA==.',
Sk='Sky:BAABLgAECn8WAAIEAAgJcCCEHwD3AgAEAAgJcCCEHwD3AgAAAA==.Skyelf:BAABLgAECn8hAAICAAgJNhCEIQCZAQACAAgJNhCEIQCZAQAAAA==.',
Sl='Sluggerr:BAABLgAECn8UAAIUAAgJWyCyCACUAgAUAAgJWyCyCACUAgAAAA==.',
Sm='Smallpox:BAAALgADCgcJCAAAAA==.Smitemedaddy:BAAALgADCgYJBQAAAA==.Smoke:BAAALgAECgMJAwAAAA==.Smokedeuce:BAAALgAECgIJAgABLgAECgMJAwAJAAAAAA==.Smokyette:BAAALgAECgMJAwAAAA==.',
So='Somira:BAAALgAECgQJBwAAAA==.Soraia:BAAALgAECgYJDwAAAA==.',
Sp='Spanktotank:BAAALgAECgUJCQAAAA==.Spectrecles:BAAALgAECgUJBQAAAA==.Spectrecless:BAAALgADCgQJBQABLgAECgUJBQAJAAAAAA==.Speez:BAABLgAECn8dAAMCAAgJAxI5GADRAQACAAgJAxI5GADRAQAkAAEJuQGMmgAYAAAAAA==.Spookyhunter:BAAALgAECggJEAAAAA==.',
St='Stablehand:BAABLgAECn8qAAICAAgJihnjDwAYAgACAAgJihnjDwAYAgAAAA==.Stephen:BAAALgADCgcJBwAAAA==.Steve:BAACLgAFFH8ZAAISAAcJUhb9AQDJAQASAAcJUhb9AQDJAQAuAAQKfyoAAhIACQkOIrQCAIIDABIACQkOIrQCAIIDAAAA.Stonedfel:BAABLgAECn8aAAIcAAgJ6w71IAC1AQAcAAgJ6w71IAC1AQAAAA==.Stonkbonkk:BAAALgAECgYJCgAAAA==.Stylez:BAAALgAECgYJCwAAAA==.',
Su='Sucsuck:BAAALgAECgMJAwAAAA==.Sundora:BAAALgAECggJEgAAAA==.Sunhoof:BAABLgAECn8WAAMlAAYJzhf7FgBlAQAlAAYJrxb7FgBlAQAZAAYJFxM3iwBkAQAAAA==.Superuberbot:BAABLgAECn8XAAIbAAYJuhEULAB8AQAbAAYJuhEULAB8AQAAAA==.Superuberdot:BAABLgAECn8ZAAQiAAYJuRY0EAArAQAiAAUJNhI0EAArAQAOAAQJqBL2awC1AAATAAEJXgBKgQAJAAAAAA==.Superuberhot:BAAALgAECgQJBQAAAA==.Superubernot:BAAALgAECgEJAgAAAA==.',
Sy='Syntacks:BAABLgAECn8dAAIEAAgJmBdtTQBOAgAEAAgJmBdtTQBOAgAAAA==.Syzara:BAAALgADCgYJCQAAAA==.',
['Sø']='Sørina:BAAALgAECgEJAQAAAA==.Sørrow:BAABLgAECn8bAAIDAAgJxw7qKABDAQADAAgJxw7qKABDAQAAAA==.',
Ta='Tabi:BAABLgAECn8hAAIEAAgJnQSgVAA3AQAEAAgJnQSgVAA3AQAAAA==.Tacts:BAAALgAECgUJBgAAAA==.Takecare:BAAALgADCgIJAwAAAA==.Tankaa:BAAALgADCgYJBwAAAA==.',
Te='Terein:BAAALgADCgEJAQAAAA==.Test:BAAALgAECgcJDAAAAA==.',
Th='Thedawg:BAAALgADCgQJBAAAAA==.Thedayman:BAAALgAECgYJBgAAAA==.Theo:BAAALgAECgEJAQAAAA==.Therwinn:BAABLgAECn8eAAICAAgJFCLcBQCaAgACAAgJFCLcBQCaAgAAAA==.Thetaint:BAABLgAECn8dAAMHAAkJmx4SAgCtAgAHAAkJNR4SAgCtAgAmAAYJlxtlBACRAQAAAA==.Thoradin:BAAALgADCgEJAQAAAA==.Thraxion:BAAALgAECgYJDwAAAA==.Thread:BAAALgAECgMJAgAAAA==.Threestorms:BAAALgADCgQJBAAAAA==.Thunderkow:BAAALgADCgcJCAABLgAFFAQJCwAOAHkgAA==.Thunderous:BAAALgAECgQJBAAAAA==.',
Ti='Tinyrunes:BAAALgAECgQJCgAAAA==.',
To='Tojiguro:BAAALgADCgYJBwAAAA==.Tommoorello:BAAALgADCgEJAQAAAA==.Torags:BAAALgADCgEJAgAAAA==.Totemofpeace:BAAALgAECggJCAABLgAECggJIQAVAGoOAA==.Towfu:BAAALgAECgYJCwAAAA==.',
Tr='Traelayn:BAAALgAECgEJAQAAAA==.Trapgawd:BAAALgADCgEJAQAAAA==.Trentlock:BAACLgAFFH8KAAIOAAQJ+A4PHgAqAQAOAAQJ+A4PHgAqAQAuAAQKfykAAxMACAkpH/UGAEYBAA4ABwkGHkYhAK4BABMABQmIG/UGAEYBAAAA.Tristae:BAAALgAECgYJDQAAAA==.Trollslingin:BAAALgADCgkJEAAAAA==.Truuk:BAAALgAECgIJAwAAAA==.',
Ts='Tsu:BAAALgADCgEJAQAAAA==.',
Tu='Tunapie:BAAALgAECgEJAgAAAA==.',
Ty='Tyzula:BAAALgAECgcJCwAAAA==.',
['Tê']='Têstament:BAAALgAECgQJBAAAAA==.',
Ub='Ubasti:BAAALgAECgcJDgAAAA==.',
Un='Unstablesha:BAAALgADCgkJEgAAAA==.',
Ur='Urahara:BAAALgAECgQJBAAAAA==.',
Va='Valiriel:BAAALgADCgcJDQAAAA==.Varsalis:BAAALgADCgMJAwAAAA==.',
Ve='Velidra:BAAALgADCgYJCQAAAA==.Vellektra:BAAALgAECgEJAQAAAA==.Vernöm:BAAALgAECgQJBAAAAA==.Vethmoree:BAAALgAECgUJBwAAAA==.',
Vi='Via:BAAALgAECgYJAwAAAA==.Vil:BAACLgAFFH8WAAIbAAgJIxiiAABxAgAbAAgJIxiiAABxAgAuAAQKfykAAhsACQk7JtgCAHoDABsACQk7JtgCAHoDAAAA.Vilonus:BAABLgAECn8cAAIOAAcJGw2LOABLAQAOAAcJGw2LOABLAQAAAA==.Virvum:BAAALgAECgQJBAAAAA==.Vitiate:BAAALgAECgMJBQAAAA==.',
Vo='Voll:BAAALgAECgYJDQAAAA==.',
Wa='Waxillium:BAAALgAECgcJCAAAAA==.',
We='Werebuddy:BAAALgADCgUJBQAAAA==.Weshyerga:BAAALgADCgYJBgABLgAFFAMJBgAYACUlAA==.',
Wi='Wigly:BAABLgAECn8XAAIfAAgJ9g1CDQC1AQAfAAgJ9g1CDQC1AQAAAA==.Willathewise:BAAALgAECgYJBgAAAA==.Wingsolid:BAAALgADCgYJCwABLgAECgUJBQAJAAAAAA==.Withengar:BAAALgAECggJEQAAAA==.',
Wr='Wrathrine:BAAALgAECgQJCQAAAA==.',
Wu='Wuoshi:BAABLgAECn8UAAMnAAgJFRKwJgB9AQAnAAgJFRKwJgB9AQAIAAEJ+RDhQwA9AAAAAA==.Wuuzzyy:BAAALgAECgYJBwAAAA==.',
Xa='Xaliko:BAABLgAECn8fAAMOAAgJKh+gCACDAgAOAAgJxR6gCACDAgATAAYJUxZHEgC6AQAAAA==.Xanathos:BAAALgADCgUJBQAAAA==.Xanbaran:BAABLgAECn8wAAIVAAkJxAmgEwB4AQAVAAkJxAmgEwB4AQAAAA==.',
Xe='Xena:BAAALgAECgUJCAABLgAECggJKQANAA0VAA==.',
Xo='Xorellion:BAABLgAECn8eAAIEAAgJoQ5fNACUAQAEAAgJoQ5fNACUAQAAAA==.',
Xy='Xyrters:BAACLgAFFH8GAAIKAAMJfQ8nDwDiAAAKAAMJfQ8nDwDiAAAuAAQKfyAAAgoACAlPIWkEAA0DAAoACAlPIWkEAA0DAAAA.',
Ye='Yeji:BAAALgADCgEJAQAAAA==.',
Yi='Yiddiephokin:BAAALgADCgYJCAAAAA==.',
Yu='Yukigodx:BAAALgADCggJEQAAAA==.Yukki:BAAALgAECgYJBgAAAA==.',
Za='Zanus:BAAALgADCgEJAQAAAA==.Zapmommy:BAAALgADCgIJAgAAAA==.Zariel:BAAALgAECgQJCQAAAA==.Zartini:BAABLgAECn8RAAIDAAgJQxe1PgDrAAADAAgJQxe1PgDrAAAAAA==.Zaylas:BAAALgADCgMJAwAAAA==.',
Ze='Zeeba:BAAALgADCgEJAQAAAA==.Zerildk:BAABLgAECn8cAAIBAAgJ1BaXJQCpAQABAAgJ1BaXJQCpAQAAAA==.Zerphaine:BAABLgAECn8eAAIMAAgJIRTUFQDVAQAMAAgJIRTUFQDVAQAAAA==.Zevs:BAABLgAECn8VAAIlAAgJdwu5GQBEAQAlAAgJdwu5GQBEAQAAAA==.',
Zi='Zic:BAABLgAECn8XAAIBAAcJbwy8PABJAQABAAcJbwy8PABJAQAAAA==.Zixxi:BAABLgAECn8nAAIEAAgJMhe/JwDGAQAEAAgJMhe/JwDGAQAAAA==.',
Zu='Zulakar:BAABLgAECn8cAAIgAAYJlxlJNgCjAQAgAAYJlxlJNgCjAQAAAA==.Zurxes:BAAALgAECgcJEAAAAA==.',
Zy='Zynatra:BAAALgAECgEJAwAAAA==.',
['Âk']='Âkaeus:BAABLgAECn8eAAISAAgJghNPEQCXAQASAAgJghNPEQCXAQAAAA==.',
['Ça']='Çaz:BAAALgADCgcJBwAAAA==.',
['Ëv']='Ëvø:BAAALgAECgMJBAAAAA==.',
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
