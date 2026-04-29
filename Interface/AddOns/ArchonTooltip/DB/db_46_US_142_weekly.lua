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

local lookup = {'Hunter-BeastMastery','Warrior-Arms','Rogue-Subtlety','Unknown-Unknown','Evoker-Preservation','DemonHunter-Devourer','DemonHunter-Vengeance','Druid-Restoration','Warlock-Demonology','Evoker-Devastation','Evoker-Augmentation','Warrior-Protection','Shaman-Elemental','Warlock-Destruction','Priest-Holy','Mage-Frost','Monk-Windwalker','Monk-Brewmaster','Paladin-Retribution','Shaman-Enhancement','Shaman-Restoration','Monk-Mistweaver','Priest-Shadow','DemonHunter-Havoc','Mage-Fire','Mage-Arcane','Priest-Discipline','DeathKnight-Unholy','Paladin-Holy','Druid-Balance','Warlock-Affliction','Hunter-Survival','Hunter-Marksmanship','Warrior-Fury','Paladin-Protection','Druid-Guardian',}
local provider = {region='US',realm="Lightning'sBlade",name='US',type='weekly',zone=46,date='2026-04-24',data={Ad='Aderai:BAAALgADCgYJCgAAAA==.',
Ae='Aeliong:BAAALgAECgEJAQAAAA==.Aendronys:BAAALgADCgQJAwAAAA==.',
Af='Afterparty:BAAALgAECgcJDwAAAA==.',
Ah='Ahmin:BAAALgADCgYJBgAAAA==.',
Ai='Aiura:BAAALgAECgQJBAAAAA==.',
Aj='Ajunlucky:BAACLgAFFH8GAAIBAAMJCxUZBwAPAQABAAMJCxUZBwAPAQAuAAQKfyQAAgEACAn6IisQALkCAAEACAn6IisQALkCAAAA.',
Al='Alagondar:BAAALgAECgYJCwAAAA==.Alakard:BAAALgAECgYJEAAAAA==.Alberich:BAAALgAECgcJDwAAAA==.Alexari:BAAALgADCgcJCwAAAA==.Alexthejoker:BAAALgADCgQJAwAAAA==.Alody:BAAALgADCgMJAwAAAA==.Althenath:BAAALgADCgMJBAAAAA==.',
Am='Amalica:BAAALgAECgUJDwAAAA==.Amenadiel:BAAALgAECgEJAQAAAA==.Amuyal:BAAALgADCgYJBgAAAA==.',
An='Anaphylactic:BAAALgAECgQJAgAAAA==.Andrea:BAAALgAECgMJBQAAAA==.Angelline:BAAALgAECgQJBQABLgAECgkJHQACAIYmAA==.Antimagi:BAAALgADCgkJCQAAAA==.',
Ap='Apheelia:BAAALgAECgQJBQAAAA==.Appypie:BAAALgAECgkJEgAAAA==.',
Ar='Arale:BAAALgADCgkJCgAAAA==.Aramala:BAAALgAECgIJAwAAAA==.Arkveld:BAABLgAECn8fAAIDAAcJDSI2DgC8AgADAAcJDSI2DgC8AgAAAA==.',
As='Ashurasenku:BAAALgAECgkJBgAAAA==.Asten:BAAALgADCgcJCwAAAA==.',
At='Athair:BAAALgAECgYJEwAAAA==.Athineana:BAAALgAECgQJBAAAAA==.',
Au='Augtistic:BAAALgAECgUJBQABLgAECgYJDgAEAAAAAA==.Aulken:BAAALgADCgEJAQAAAA==.',
Ay='Aylinn:BAABLgAECn8XAAIFAAYJPiBnAgDvAQAFAAYJPiBnAgDvAQAAAA==.Aylira:BAAALgAECgQJCAAAAA==.Aymonzo:BAABLgAECn8UAAMGAAYJYBfTWwCOAQAGAAYJYBfTWwCOAQAHAAEJ3g3iCwArAAAAAA==.',
Az='Azem:BAAALgADCgkJDAAAAA==.',
Ba='Badlóck:BAAALgAECgcJBQAAAA==.Baharrar:BAABLgAECn8YAAIIAAgJQSL2CQD1AgAIAAgJQSL2CQD1AgAAAA==.Barofslovr:BAAALgADCgcJBwABLgAECgYJDQAEAAAAAA==.Barrylowmana:BAAALgADCgcJBwAAAA==.Bartendresse:BAAALgAECgEJAQAAAA==.Bastrasz:BAAALgAECgcJBAAAAA==.Batar:BAAALgADCgYJBgAAAA==.',
Be='Bearalas:BAACLgAFFH8IAAIJAAQJyA9cEADxAAAJAAQJyA9cEADxAAAuAAQKfxUAAgkACQkfHG0YAMICAAkACQkfHG0YAMICAAAA.Bearis:BAAALgADCgMJAwAAAA==.Beekin:BAAALgAECgUJCwAAAA==.Beeyah:BAABLgAECn8XAAIBAAgJbBrFIQA7AgABAAgJbBrFIQA7AgAAAA==.Beldion:BAAALgADCgUJBQABLgAECgUJCwAEAAAAAA==.Bellator:BAAALgADCgMJAwAAAA==.Bellona:BAAALgADCgQJBAAAAA==.Bernarnold:BAAALgAECgYJEAAAAA==.Bettyspready:BAAALgAECgYJCAAAAA==.',
Bi='Bigoysters:BAAALgAECgIJAgAAAA==.Bigpoppapump:BAAALgAECgYJEwAAAA==.Bigthumbb:BAAALgAECgEJAQAAAA==.Bikook:BAAALgADCgIJAgABLgAECggJFAAFAIwLAA==.Binnyi:BAABLgAECn8dAAMKAAgJ9AlGAwAxAQAKAAgJ9AlGAwAxAQALAAYJogbnPAD6AAAAAA==.Biwwy:BAAALgAECgEJAQAAAA==.',
Bl='Blabidil:BAAALgADCgQJBAAAAA==.Blackfoot:BAAALgAECgYJEgAAAA==.Blackyeshua:BAACLgAFFH8GAAILAAMJLAZVCgDVAAALAAMJLAZVCgDVAAAuAAQKfyYAAgsACAndGqkGAIwBAAsACAndGqkGAIwBAAAA.Blastphemy:BAAALgADCgYJBgAAAA==.Blindpov:BAAALgADCggJCQAAAA==.',
Bo='Boanhead:BAAALgADCgIJAgAAAA==.Boomtiloom:BAAALgADCgMJAwAAAA==.Borgastraz:BAAALgAECgYJCgAAAA==.Boru:BAAALgADCgcJBwAAAA==.Boshin:BAAALgAECgEJAQAAAA==.Boshintime:BAAALgAECgMJAwAAAA==.Bouberry:BAAALgAECgYJEwAAAA==.',
Br='Brewstoes:BAAALgADCgQJBQAAAA==.Bricksquadx:BAAALgAECgMJBQAAAA==.Brink:BAAALgADCgIJAgAAAA==.Broki:BAAALgAECgEJAQAAAA==.Brugnir:BAAALgAECgYJBgABLgAECgUJBwAEAAAAAA==.Bruwen:BAAALgADCgcJCAABLgAECgYJDgAEAAAAAA==.',
Bu='Bubblegruff:BAAALgADCgYJCQAAAA==.Bubbleohsevn:BAAALgAECgEJAQAAAA==.Bubblesaurus:BAAALgAECgYJEQAAAA==.Bum:BAAALgADCgkJCQAAAA==.Burlan:BAAALgAECgYJDwAAAA==.',
['Bé']='Béåst:BAAALgAECgYJDwAAAA==.',
['Bë']='Bërshton:BAAALgAECgYJCAAAAA==.',
Ca='Cakeshake:BAAALgAECgMJBQAAAA==.Caleris:BAABLgAECn8XAAIMAAgJrRAJBQBtAQAMAAgJrRAJBQBtAQAAAA==.Camelnuckle:BAABLgAECn8fAAINAAgJZBWUCQBjAQANAAgJZBWUCQBjAQAAAA==.Car:BAAALgADCgIJAgAAAA==.Cattle:BAAALgAECgcJDwAAAA==.',
Ch='Chaosglaive:BAAALgAECgcJEgAAAA==.Chaostorms:BAAALgAECgUJCgAAAA==.Chess:BAAALgAECgYJCwAAAA==.Chickenhydra:BAAALgADCgYJBgAAAA==.Chlorophil:BAAALgADCgYJBwAAAA==.Choochew:BAAALgAECgEJAgAAAA==.Chowlock:BAABLgAECn8dAAMOAAgJRSPcAgDTAgAOAAcJmiPcAgDTAgAJAAQJFyI7awCMAQAAAA==.Chowmantwo:BAAALgADCgEJAQAAAA==.',
Cl='Classicmonk:BAAALgAECgEJAQAAAA==.Clawsofpeace:BAAALgADCgkJDQABLgAECggJIQAPAGoOAA==.Cleverboi:BAAALgADCgYJBgAAAA==.',
Co='Constancia:BAAALgAECgQJCAAAAA==.',
Cr='Crackahjack:BAAALgAECgEJAQAAAA==.Craigor:BAAALgADCgcJCAABLgAECgcJEAAEAAAAAA==.Croppydust:BAAALgADCgcJDAAAAA==.Cryden:BAAALgADCgMJAwAAAA==.',
Cy='Cylicmylic:BAAALgAECgQJBAAAAA==.',
Cz='Czark:BAAALgAECgQJBAAAAA==.',
Da='Dalamaar:BAAALgADCgEJAQAAAA==.Dandey:BAAALgAECgEJAQAAAA==.Dangerdoom:BAAALgADCgEJAQABLgAECggJGwAQAJgXAA==.Dantee:BAABLgAECn8XAAIHAAgJqRrrAwCKAgAHAAgJqRrrAwCKAgAAAA==.Daps:BAAALgADCgcJCgAAAA==.Darkfoxgrime:BAABLgAECn8UAAIRAAgJ1QisOgAyAQARAAgJ1QisOgAyAQAAAA==.Datsmywife:BAAALgAFFAEJAQAAAA==.',
De='Deadvikingg:BAAALgAECgcJBwAAAA==.Deebss:BAAALgAECgEJAQAAAA==.Degradation:BAAALgAECgEJAwAAAA==.Degru:BAAALgAECgYJDgAAAA==.Delaire:BAAALgAECgYJCAAAAA==.Demonkow:BAACLgAFFH8IAAIJAAMJSyAeFwA3AQAJAAMJSyAeFwA3AQAuAAQKfyAAAwkACAnuIiUDAGcCAAkABwmmIiUDAGcCAA4ABAkPIgwbAHUBAAAA.Dereksama:BAAALgADCgQJBAAAAA==.Destrah:BAAALgADCgUJBQAAAA==.Deviiarrc:BAACLgAFFH8HAAIFAAIJBSF0BgDEAAAFAAIJBSF0BgDEAAAuAAQKfyAAAgUACAl5JCIDADUDAAUACAl5JCIDADUDAAAA.',
Di='Dikan:BAAALgADCgEJAQAAAA==.Dinosaurman:BAAALgAECgQJBAAAAA==.Disintegrate:BAAALgAECgcJBwABLgAFFAQJCQALAI8WAA==.',
Do='Doova:BAAALgADCgYJCgAAAA==.Dorik:BAAALgADCgYJBgAAAA==.',
Dr='Dracar:BAAALgAECgQJDQAAAA==.Drackian:BAAALgAECgQJBAAAAA==.Dragondyne:BAAALgAECggJCAABLgAECgkJJwASADAaAA==.Drdurun:BAAALgADCgYJBwAAAA==.Drekavak:BAAALgAECgYJCAAAAA==.Drekfur:BAAALgADCgcJCgAAAA==.Drmmrfist:BAABLgAECn8iAAISAAgJ0hMxCAB1AQASAAgJ0hMxCAB1AQAAAA==.Druideca:BAAALgAECgYJDgAAAA==.',
Dw='Dwippietiggs:BAABLgAECn8iAAITAAgJrh3BBQA6AgATAAgJrh3BBQA6AgAAAA==.',
Ea='Earthfeather:BAAALgADCgIJAgAAAA==.',
Ec='Echoesonmute:BAAALgADCgEJAQAAAA==.',
Ed='Edhochuli:BAAALgADCgUJBQABLgADCgYJBgAEAAAAAA==.',
Ee='Eetee:BAABLgAECn8aAAQNAAgJFw+AKwC7AQANAAgJFw+AKwC7AQAUAAQJNQvHHwDVAAAVAAUJGw0LGwDAAAAAAA==.',
Ek='Ekitten:BAAALgAECgYJCwABLgAFFAQJCQAWAOokAA==.Ekitty:BAAALgAECgYJEQABLgAFFAQJCQAWAOokAA==.',
El='Elandria:BAAALgAECgYJEAAAAA==.Elohym:BAAALgADCgUJBQAAAA==.Elsea:BAAALgAECgEJAQAAAA==.',
Em='Emberstone:BAAALgAECgEJAQAAAA==.Emotions:BAAALgAECgUJCwAAAA==.',
Ep='Epicdragon:BAAALgAECgMJAwAAAA==.',
Eq='Equesmortis:BAAALgAECgYJDgAAAA==.',
Er='Erös:BAAALgAECgUJCQAAAA==.',
Et='Etatoned:BAAALgADCggJEQAAAA==.Etengaged:BAAALgAECgMJBAAAAA==.Ethavoc:BAAALgADCgQJBAAAAA==.',
Eu='Eurdice:BAAALgADCgIJAgAAAA==.',
Ev='Evo:BAAALgADCgUJBQABLgAECggJHwAQANMaAA==.Evrae:BAAALgAECgYJCgAAAA==.',
Ex='Extragrace:BAAALgAECgYJCwAAAA==.',
Fa='Faithshand:BAABLgAECn8dAAMPAAgJ5wi0PQBDAQAPAAgJ5wi0PQBDAQAXAAQJBgP2FQChAAAAAA==.Fallenbow:BAAALgAECgUJBQAAAA==.Fappa:BAABLgAECn8mAAIJAAkJLg0ODAC5AQAJAAkJLg0ODAC5AQAAAA==.',
Fe='Featherstone:BAAALgADCgIJAwAAAA==.Feelzdope:BAAALgADCgQJBAAAAA==.Feio:BAABLgAECn8dAAIYAAgJgh/qAQARAgAYAAgJgh/qAQARAgAAAA==.Felfirez:BAAALgAECgEJAQAAAA==.Felydrak:BAABLgAECn8WAAMKAAgJkhOBDQABAgAKAAgJkhOBDQABAgAFAAMJfgbmCwB8AAAAAA==.Fergilicious:BAAALgAECgYJDQAAAA==.',
Fi='Finkenator:BAACLgAFFH8PAAIQAAUJ6BoqFwBtAQAQAAUJ6BoqFwBtAQAuAAQKfx8AAhAACAnXJbIKAG4DABAACAnXJbIKAG4DAAAA.Finkler:BAABLgAECn8jAAIQAAkJEyG7DgBRAwAQAAkJEyG7DgBRAwABLgAFFAUJDwAQAOgaAA==.Firedanny:BAAALgAECgIJAwAAAA==.',
Fl='Flameshock:BAABLgAECn8bAAQZAAgJ5wwBBQB7AQAZAAcJAQoBBQB7AQAQAAQJdwNzJwGyAAAaAAIJ1BEuBACIAAAAAA==.Flippybippi:BAAALgAECgEJAQAAAA==.Flixur:BAABLgAECn8ZAAIQAAcJVR0jDADvAQAQAAcJVR0jDADvAQAAAA==.Flyzikman:BAAALgADCgEJAQAAAA==.',
Fo='Forté:BAAALgADCgMJAwAAAA==.',
Fr='Freek:BAAALgAECgEJAQAAAA==.Freewillie:BAAALgAECgEJAQABLgAECgQJBgAEAAAAAA==.Friarmj:BAABLgAECn8iAAIbAAgJsgpJBgCaAQAbAAgJsgpJBgCaAQAAAA==.Frigidbeach:BAAALgAECgYJEAAAAA==.Frozeny:BAAALgADCgcJDQAAAA==.',
Fu='Furrita:BAAALgADCgcJBwAAAA==.',
Ga='Gainesta:BAAALgAECgYJDAAAAA==.Galazeth:BAAALgAECgcJDQABLgAECgcJHQAcAMAjAA==.Gamthor:BAAALgAECgcJEAAAAA==.',
Gi='Gildeddash:BAAALgAECgYJDwAAAA==.Giudice:BAAALgADCgkJDAAAAA==.',
Gl='Glengoyne:BAAALgAECgMJBgAAAA==.Globoe:BAACLgAFFH8XAAMKAAgJeR5GAAD/AQAKAAUJeyRGAAD/AQALAAUJDxoLCABvAQAuAAQKfykAAwoACQknJkIAAMsDAAoACQnWJUIAAMsDAAsACAmCInYNAJ4CAAAA.Gluggther:BAAALgADCgkJDAAAAA==.',
Go='Goru:BAAALgADCgYJBgAAAA==.',
Gr='Grahz:BAAALgAECgEJAQAAAA==.Gravyboat:BAAALgAECgYJDgAAAA==.Graydawn:BAAALgADCgcJCQAAAA==.Grimwillie:BAAALgAECgQJBgAAAA==.Grismago:BAAALgAECgEJAgAAAA==.',
Gu='Gusto:BAAALgAECgIJAwAAAA==.',
['Gë']='Gënghiskhän:BAAALgADCgUJBQAAAA==.',
Ha='Haakon:BAAALgADCgEJAQAAAA==.Harrowing:BAABLgAECn8lAAIdAAgJMB63AgBoAgAdAAgJMB63AgBoAgAAAA==.Haurt:BAABLgAECn8aAAIeAAgJJxKKCABqAQAeAAgJJxKKCABqAQAAAA==.Havoq:BAAALgAECgMJAwAAAA==.',
He='Healamore:BAAALgADCgEJAgAAAA==.Healingway:BAAALgADCgUJBQABLgADCgYJBgAEAAAAAA==.Heavyhooves:BAAALgAECgYJDwAAAA==.Helawix:BAAALgADCgQJBAAAAA==.Hellful:BAAALgAECgcJCQAAAA==.Hellscrèam:BAAALgAECgMJBQAAAA==.Herc:BAAALgAECgEJAQAAAA==.',
Hi='Hischier:BAABLgAECn8aAAMfAAYJ6xwkBwDkAQAfAAYJ6xwkBwDkAQAJAAYJ+AlOHwAlAQAAAA==.',
Ho='Holyjoey:BAAALgAECgYJCQAAAA==.Holymôley:BAABLgAECn8ZAAIVAAgJNyJOBgANAwAVAAgJNyJOBgANAwAAAA==.Holytroller:BAAALgAECgUJCAAAAA==.Horrorcosmic:BAAALgADCgEJAQAAAA==.Hotbeeframen:BAAALgADCgEJAQAAAA==.',
Hu='Hulken:BAAALgADCgYJBgAAAA==.Humanpriest:BAAALgADCgEJAQABLgADCgkJCQAEAAAAAA==.Hussongs:BAAALgAECgEJAQAAAA==.',
['Hû']='Hûnta:BAAALgADCgQJBAAAAA==.',
Ie='Ieratha:BAAALgADCgcJFQAAAA==.',
Il='Illidanina:BAAALgADCgUJBQABLgAFFAYJEgAfALMkAA==.',
In='Invi:BAABLgAECn8bAAMdAAgJmxx2EACPAgAdAAgJmxx2EACPAgATAAYJpRTofACAAQAAAA==.',
It='Itkøvian:BAAALgAECggJCAAAAA==.',
Ja='Jarrickah:BAAALgAECgQJBAAAAA==.Jaycito:BAAALgAECgYJCwAAAA==.Jayylols:BAAALgAECgEJAQAAAA==.',
Je='Jeor:BAAALgAECgQJCAAAAA==.',
Ji='Jigsy:BAABLgAECn8YAAMJAAkJxx5JIwCHAgAJAAgJxx5JIwCHAgAOAAMJBx+ILAAMAQAAAA==.Jigy:BAAALgAECgYJDAAAAA==.Jimmy:BAAALgADCgcJBwAAAA==.',
Jo='Jokerzwild:BAAALgADCgQJBAAAAA==.Jorker:BAABLgAECn8YAAIGAAgJtR0KGgC4AgAGAAgJtR0KGgC4AgAAAA==.Jovinistus:BAAALgADCgcJDwAAAA==.',
Ju='Judgecutìe:BAAALgAECgcJDQAAAA==.Jue:BAAALgAECgEJBAAAAA==.Juiice:BAAALgADCgcJBwAAAA==.',
['Jë']='Jësus:BAAALgAECgUJCQAAAA==.',
Ka='Kamisama:BAAALgADCgYJCQAAAA==.Kawalskie:BAAALgAECgQJBQAAAA==.Kazraghand:BAABLgAECn8iAAIgAAgJHAgKBwBLAQAgAAgJHAgKBwBLAQAAAA==.',
Ke='Kei:BAACLgAFFH8FAAIGAAMJ+g3vHQDmAAAGAAMJ+g3vHQDmAAAuAAQKfygAAwYACAmVHjIDAHICAAYACAmVHjIDAHICABgAAQkYDGNxADMAAAAA.Kelsio:BAABLgAECn8ZAAIBAAgJKQ17MADvAQABAAgJKQ17MADvAQAAAA==.Kess:BAAALgAECgYJCAAAAA==.Keyboardcatt:BAAALgAECgYJEQAAAA==.',
Kh='Kharos:BAABLgAECn8gAAMPAAgJDAmHOwBNAQAPAAgJ0gWHOwBNAQAbAAcJKAfgMwAEAQAAAA==.',
Ki='Kidneyshot:BAAALgAECgEJAgABLgAFFAQJCQALAI8WAA==.Kikeo:BAAALgAECgQJBAABLgAFFAMJBQAGAPoNAA==.Killerwarz:BAAALgADCgYJCQAAAA==.Kirkoth:BAAALgADCgkJFwAAAA==.Kitariya:BAAALgADCgIJAgAAAA==.',
Kn='Knuts:BAABLgAECn8ZAAMOAAcJPQJjOwDGAAAOAAcJFQJjOwDGAAAJAAYJzAEQ+ABpAAAAAA==.',
Ko='Kogori:BAAALgAECgUJCgAAAA==.Konsentrated:BAAALgAECgYJDgAAAA==.Kowtagion:BAAALgADCgYJBgABLgAFFAMJCAAJAEsgAA==.',
Ku='Kuraven:BAAALgADCgcJBwAAAA==.Kuromo:BAAALgADCgMJAwAAAA==.',
Ky='Kylidan:BAAALgAECgEJAgAAAA==.Kyradin:BAAALgADCgIJAgABLgADCgYJDAAEAAAAAA==.Kyruutos:BAAALgAECgYJEAAAAA==.Kyvoker:BAAALgAECgQJBQAAAA==.',
['Kí']='Kítkat:BAABLgAECn8bAAIVAAgJPhopFgBkAgAVAAgJPhopFgBkAgAAAA==.',
La='Lachulax:BAAALgADCgYJDgAAAA==.Lacie:BAAALgAECgMJBwAAAA==.',
Le='Legato:BAAALgAECgEJAgAAAA==.Leibowitzy:BAAALgAECgUJCwAAAA==.Lettucee:BAAALgADCgYJBgAAAA==.Lexstrasza:BAAALgADCgEJAgAAAA==.',
Lh='Lhehitman:BAABLgAECn8hAAMQAAgJHCCQNwCWAgAQAAgJHCCQNwCWAgAaAAMJphMuEgChAAAAAA==.',
Li='Lifedeath:BAAALgADCgMJAwAAAA==.Lightsey:BAAALgAECgQJBAAAAA==.Lilth:BAAALgADCgkJCQAAAA==.Lindalamage:BAAALgADCgQJBQAAAA==.Linebreaker:BAAALgAECgcJDwAAAA==.Litezamatch:BAAALgADCgIJAgAAAA==.Liveloveslay:BAAALgAECgkJBQAAAA==.',
Lo='Loreena:BAAALgADCgIJAgAAAA==.Lorein:BAAALgAECgEJAQAAAA==.',
Lu='Luckydog:BAAALgAECgQJBwABLgAECgYJCwAEAAAAAA==.Ludey:BAABLgAECn8nAAMfAAkJ6RWQAgCUAgAfAAkJ6RWQAgCUAgAJAAEJYASgWQAwAAAAAA==.Lutnick:BAAALgAECgEJAQAAAA==.Lutray:BAABLgAECn8dAAIMAAgJ7yPLAACDAgAMAAgJ7yPLAACDAgAAAA==.',
Ly='Lysandriloc:BAABLgAECn8YAAQOAAYJcREAOgDMAAAOAAUJlwUAOgDMAAAJAAYJLA4gMwC2AAAfAAMJEBKzHACNAAAAAA==.',
Ma='Madcowdíseaz:BAAALgAECgYJDAAAAA==.Madskadoosh:BAAALgADCgEJAQAAAA==.Madtotems:BAAALgAECgcJEgAAAA==.Magnator:BAAALgAECgMJAwAAAA==.Malanore:BAAALgAECgcJEgAAAA==.Manbeartree:BAAALgAECgIJAgABLgAFFAQJCgAdAPgeAA==.Manbeärpig:BAAALgAECgQJBwAAAA==.Maomao:BAABLgAECn8ZAAIPAAgJChpVEABiAgAPAAgJChpVEABiAgAAAA==.Marodd:BAABLgAECn8cAAIXAAgJ5B5RAwADAgAXAAgJ5B5RAwADAgAAAA==.Mashîra:BAAALgAFFAEJAQABLgAECggJHQANAB0iAA==.Matilda:BAAALgAECgEJAQAAAA==.Matylin:BAAALgADCgEJAQAAAA==.Maximus:BAAALgAECgYJDgAAAA==.',
Me='Meanmachine:BAAALgADCgIJAgAAAA==.Meatpocket:BAAALgADCgUJBQAAAA==.Meatwangs:BAAALgAECgYJCgAAAA==.Meleguar:BAAALgADCgIJBAAAAA==.Merihem:BAAALgADCggJDgAAAA==.Merpz:BAAALgADCgYJCwAAAA==.',
Mi='Mia:BAAALgAFFAEJAQAAAA==.Miamore:BAAALgADCgEJAQABLgADCgkJCQAEAAAAAA==.Milize:BAAALgAECgIJAgAAAA==.Milknkookies:BAAALgAECgIJAgAAAA==.Miney:BAAALgADCgkJEQAAAA==.Misc:BAAALgAECgMJAwAAAA==.Mistaeatit:BAABLgAECn8XAAIcAAcJQSKsLgB9AgAcAAcJQSKsLgB9AgAAAA==.Mitch:BAAALgAECgQJCAAAAA==.',
Mk='Mkachen:BAAALgADCgUJBQAAAA==.',
Mo='Moondotter:BAAALgAECgMJBQAAAA==.Moonslayer:BAAALgAECggJDQAAAA==.Moovefool:BAAALgAECgYJCQAAAA==.Mortimer:BAABLgAECn8dAAIcAAgJeBcfDgCqAQAcAAgJeBcfDgCqAQAAAA==.',
Mu='Mudgeon:BAAALgAECgYJEQAAAA==.Mulheron:BAAALgADCgMJBAAAAA==.Mulletmonk:BAAALgAECgQJCAAAAA==.',
['Mâ']='Mâshîrâ:BAABLgAECn8dAAMNAAgJHSKdCgDsAgANAAgJHSKdCgDsAgAUAAMJwApFJACVAAAAAA==.',
Na='Nagarafan:BAAALgAECgYJDQAAAA==.Nakor:BAAALgAECgcJEgAAAA==.Natalie:BAAALgAECgQJBgAAAA==.',
Ne='Nefariat:BAAALgAECgMJAwAAAA==.Nefarious:BAAALgAECgEJAQABLgAECgMJAwAEAAAAAA==.Nefeli:BAABLgAECn8nAAMLAAkJUxdQAwD4AQAKAAgJexg/CgA6AgALAAkJDA9QAwD4AQAAAA==.Nelinne:BAABLgAECn8XAAMgAAcJPAEADgCXAAAgAAcJLgEADgCXAAABAAMJDgFZygA7AAAAAA==.Nestia:BAAALgAECgQJBwAAAA==.Never:BAACLgAFFH8HAAIJAAMJ2h4ZCgAnAQAJAAMJ2h4ZCgAnAQAuAAQKfyUAAwkACQllI8sBALQDAAkACQllI8sBALQDAA4ABQnxIGsPANYBAAAA.',
Ni='Niccolò:BAAALgADCgEJAQAAAA==.Nidis:BAAALgADCgYJAQAAAA==.Nieve:BAAALgADCgEJAQAAAA==.Nightarrow:BAABLgAECn8aAAMBAAcJLBBzEgBoAQABAAcJLBBzEgBoAQAhAAEJKwBAnAAKAAAAAA==.Nightbird:BAAALgAECgcJAQAAAA==.Nightshade:BAABLgAECn8jAAMBAAgJjBibBQAaAgABAAgJjBibBQAaAgAhAAgJQwv/OAB9AQAAAA==.Nil:BAAALgAECgYJCgAAAA==.Ninjamonkggz:BAAALgAECgkJEgAAAA==.Nitron:BAAALgAECgcJAgAAAA==.Nix:BAABLgAECn8dAAIQAAgJfBPKEQC0AQAQAAgJfBPKEQC0AQAAAA==.',
No='Noanelororal:BAAALgAECgEJAQAAAA==.Nortney:BAABLgAECn8VAAIiAAgJ7RjmGgB1AgAiAAgJ7RjmGgB1AgAAAA==.Noskilzreq:BAAALgAECgQJBwAAAA==.Nostrum:BAAALgAECgYJBgAAAA==.Noughts:BAAALgADCgEJAQAAAA==.Novva:BAAALgAECgEJAQAAAA==.',
Ny='Nyckels:BAAALgADCgEJAQAAAA==.',
Oa='Oathbound:BAAALgADCgEJAQAAAA==.',
Ob='Oblaan:BAABLgAECn8cAAQJAAgJKR+rBgAJAgAJAAYJrR6rBgAJAgAOAAUJSR2SFgCVAQAfAAEJHCKLJwBTAAAAAA==.',
Oc='Ocllo:BAABLgAECn8dAAIjAAgJQRLbFQBzAQAjAAgJQRLbFQBzAQAAAA==.',
Oj='Ojo:BAAALgAECgYJEQAAAA==.',
On='Onebuttonaug:BAAALgAECgYJBgABLgAFFAcJFAANAGQUAA==.Oniana:BAABLgAECn8bAAIhAAcJQAxhCADdAAAhAAcJQAxhCADdAAAAAA==.',
Oo='Oozle:BAAALgADCgEJAgAAAA==.',
Op='Openwide:BAAALgADCgMJAwABLgADCgYJBgAEAAAAAA==.Oprahwinfuri:BAAALgADCgYJBgAAAA==.',
Or='Orccrusher:BAAALgADCgQJBwAAAA==.',
Pa='Pagamas:BAABLgAECn8ZAAIQAAgJPyIfMACyAgAQAAgJPyIfMACyAgAAAA==.Painbringer:BAAALgAECgIJAgAAAA==.Pajano:BAAALgADCgcJDAAAAA==.Palandari:BAAALgADCgkJAQAAAA==.Palawin:BAAALgADCgkJCQAAAA==.Pandawan:BAAALgADCgkJDAAAAA==.Panter:BAAALgAECgQJCAAAAA==.',
Pe='Peachpear:BAAALgAECgYJDwAAAA==.',
Ph='Pharaoh:BAABLgAECn8cAAIXAAcJRhQ+IgDFAQAXAAcJRhQ+IgDFAQAAAA==.Phodoe:BAABLgAECn8dAAIIAAgJcwt+FAAjAQAIAAgJcwt+FAAjAQAAAA==.Phycara:BAAALgAECgIJAgAAAA==.Phyronix:BAAALgADCgkJDAAAAA==.',
Pi='Pickawp:BAAALgAECgQJBAAAAA==.',
Pl='Playne:BAABLgAECn8bAAIQAAgJiBhmEQC3AQAQAAgJiBhmEQC3AQAAAA==.',
Pn='Pnzr:BAAALgAECgcJCgAAAA==.',
Po='Pokeureyeout:BAAALgAECgMJBQAAAA==.Poofarts:BAAALgAECgEJAQAAAA==.Poostorclose:BAAALgAECgQJBQAAAA==.Pootonium:BAAALgAECgYJCgAAAA==.Popaul:BAAALgADCgYJCwAAAA==.',
Pr='Prahn:BAABLgAECn8iAAIVAAkJvg1XPQCMAQAVAAkJvg1XPQCMAQAAAA==.Preaced:BAABLgAECn8hAAIPAAgJag4nCACBAQAPAAgJag4nCACBAQAAAA==.Prokix:BAAALgAECgUJDAAAAA==.Propainiac:BAAALgAECgQJBAAAAA==.',
Pu='Pumpkinpuff:BAABLgAECn8WAAIWAAYJKyJ7BADtAQAWAAYJKyJ7BADtAQAAAA==.',
['Pî']='Pîlot:BAAALgADCgkJCQABLgAECgYJDQAEAAAAAA==.',
Qu='Quiet:BAAALgAECgEJAQAAAA==.Quiettreader:BAAALgAECgUJCwAAAA==.Quokka:BAAALgAECgYJEAAAAA==.',
Ra='Raambocatt:BAAALgADCgUJBQAAAA==.Raidboss:BAAALgAECgYJDAAAAA==.Raklem:BAABLgAECn8YAAMBAAcJlRAqTACEAQABAAcJlRAqTACEAQAhAAQJygNVbQCJAAAAAA==.Rampage:BAAALgADCgYJBgABLgAECgUJCwAEAAAAAA==.Ramssox:BAAALgAECgEJAQAAAA==.Raty:BAAALgAECgIJAgAAAA==.',
Re='Redeath:BAAALgAECgMJBQABLgAECggJIgATAK4SAA==.Redirect:BAAALgADCgcJFQABLgAECggJIgATAK4SAA==.Redonculous:BAAALgAECgQJBQAAAA==.Redpool:BAAALgAECgEJAQAAAA==.Reinault:BAACLgAFFH8GAAIRAAMJjwvgAwDrAAARAAMJjwvgAwDrAAAuAAQKfx4AAxEACAnLGsAVADwCABEACAnLGsAVADwCABYABwnPCOQ4AAkBAAAA.Reiramas:BAAALgAECgUJBQAAAA==.Relentful:BAAALgADCgIJAgAAAA==.Reliea:BAAALgAECgMJBAAAAA==.Renalla:BAAALgADCgYJBwAAAA==.Revansong:BAAALgAECgUJCAABLgAECgcJHwADAA0iAA==.',
Ri='Rika:BAAALgADCgYJBgAAAA==.',
Ro='Ronx:BAABLgAECn8WAAIQAAcJfBaUFQCWAQAQAAcJfBaUFQCWAQAAAA==.Roodfrost:BAAALgADCgUJBwAAAA==.Roxxiloxxi:BAABLgAECn8XAAMOAAgJYgS1LgABAQAOAAgJ+QO1LgABAQAJAAQJUQNMNgCjAAAAAA==.Royal:BAABLgAECn8hAAIkAAgJDRUyAwB7AQAkAAgJDRUyAwB7AQAAAA==.',
Ru='Rudeboy:BAAALgADCgIJAgAAAA==.Ruination:BAAALgAECgEJAgAAAA==.Rukìa:BAAALgADCgUJBQABLgAECgYJDgAEAAAAAA==.',
Sa='Sabria:BAABLgAECn8nAAMdAAkJfxeSAQCnAgAdAAkJfxeSAQCnAgATAAgJ1A7eXADMAQAAAA==.Sahee:BAAALgADCgMJAwAAAA==.Sahria:BAAALgAECgQJCAAAAA==.Samlosco:BAAALgAECgYJEQAAAA==.Saninth:BAAALgAECgEJAQAAAA==.Satra:BAAALgADCggJCAAAAA==.Savus:BAAALgADCgMJAwAAAA==.',
Sc='Scalpelheals:BAACLgAFFH8XAAIbAAgJ7g2BAQAnAgAbAAgJ7g2BAQAnAgAuAAQKfy0ABBsACQmMJLsAAKsDABsACQmqI7sAAKsDAA8ABwnvGvYbAP0BABcAAQkeCQxiADQAAAAA.Sceledrus:BAAALgADCgcJDQAAAA==.Schizadin:BAAALgAECgEJAQAAAA==.Schizology:BAAALgADCgkJDAAAAA==.',
Se='Sebekuul:BAAALgAECgUJBQAAAQ==.Selbur:BAAALgADCgMJAwABLgAFFAUJCgARAAEYAA==.Selfie:BAAALgADCgEJAgAAAA==.Sence:BAAALgAECgEJAQAAAA==.Sendy:BAAALgAECgYJBwAAAA==.Sephurik:BAACLgAFFH8PAAIQAAgJ/gy0AgBaAgAQAAgJ/gy0AgBaAgAuAAQKfy0AAhAACQm0I3EIAIMDABAACQm0I3EIAIMDAAAA.Sepimoth:BAAALgADCgYJBgAAAA==.Septicaemia:BAAALgAECgMJAwAAAA==.Serovin:BAAALgADCgcJBwAAAA==.',
Sh='Shaolin:BAAALgADCgUJBQABLgAECgYJDgAEAAAAAA==.Sheepie:BAAALgADCgMJAwAAAA==.Shindorei:BAAALgAECgMJAwAAAA==.Shintai:BAAALgAECgUJDwAAAA==.Shnicklfritz:BAAALgADCgQJBQAAAA==.Showtek:BAABLgAECn8bAAIkAAcJqxmyCgDrAQAkAAcJqxmyCgDrAQAAAA==.Shyft:BAAALgAECgYJDgAAAA==.Shyfty:BAAALgAECgMJAwABLgAECgYJDgAEAAAAAA==.Shîn:BAABLgAECn8VAAQTAAcJoxegJQAQAQATAAcJUhSgJQAQAQAjAAMJGQ0gMgCFAAAdAAIJXAWdigBTAAAAAA==.',
Si='Sickology:BAAALgAECgQJBgAAAA==.Sikanda:BAABLgAECn8dAAIcAAcJwCPWIAC+AgAcAAcJwCPWIAC+AgAAAA==.Simplord:BAAALgAECgMJBAAAAA==.Sinara:BAAALgAECgMJCAAAAA==.Sintaxtwo:BAACLgAFFH8JAAMBAAQJQR3sAQBxAQABAAQJPxjsAQBxAQAhAAMJzhmfEwADAQAuAAQKfx4AAiEACAnFIyAIABoDACEACAnFIyAIABoDAAAA.Sion:BAABLgAECn8bAAIXAAgJtB6kAQBiAgAXAAgJtB6kAQBiAgAAAA==.Sithlordz:BAAALgAECgIJAgAAAA==.',
Sk='Sky:BAABLgAECn8WAAIQAAgJcCCDHwD3AgAQAAgJcCCDHwD3AgAAAA==.Skyelf:BAABLgAECn8ZAAIBAAgJNQ6xLgD3AQABAAgJNQ6xLgD3AQAAAA==.',
Sl='Sluggerr:BAAALgAECggJDwAAAA==.',
Sm='Smallpox:BAAALgADCgcJCAAAAA==.Smitemedaddy:BAAALgADCgYJBQAAAA==.Smoke:BAAALgAECgMJAwAAAA==.Smokedeuce:BAAALgAECgIJAgABLgAECgMJAwAEAAAAAA==.Smokyette:BAAALgAECgMJAwAAAA==.',
So='Somira:BAAALgAECgQJBAAAAA==.Soraia:BAAALgAECgUJCgAAAA==.',
Sp='Spanktotank:BAAALgAECgQJBAAAAA==.Spectrecles:BAAALgADCgUJBgABLgADCgYJBgAEAAAAAA==.Spectrecless:BAAALgADCgQJBQABLgADCgYJBgAEAAAAAA==.Speez:BAABLgAECn8WAAMBAAcJERGBFQBPAQABAAcJERGBFQBPAQAhAAEJuQGImgAYAAAAAA==.Spookyhunter:BAAALgAECggJCAAAAA==.',
St='Stablehand:BAABLgAECn8jAAIBAAgJUhQ6CgDGAQABAAgJUhQ6CgDGAQAAAA==.Stephen:BAAALgADCgcJBwAAAA==.Steve:BAACLgAFFH8UAAINAAcJZBRMAgDfAQANAAcJZBRMAgDfAQAuAAQKfycAAg0ACQkOIrACAIIDAA0ACQkOIrACAIIDAAAA.Stonedfel:BAABLgAECn8UAAIYAAgJlg74IAC1AQAYAAgJlg74IAC1AQAAAA==.Stonkbonkk:BAAALgAECgQJBAAAAA==.Stylez:BAAALgAECgYJCwAAAA==.',
Su='Sucsuck:BAAALgAECgMJAwAAAA==.Sundora:BAAALgAECgYJCQAAAA==.Sunhoof:BAAALgAECgYJDwAAAA==.Superuberbot:BAABLgAECn8WAAIXAAYJuhERLAB8AQAXAAYJuhERLAB8AQAAAA==.Superuberdot:BAABLgAECn8UAAQfAAYJgRY0EAArAQAfAAUJNhI0EAArAQAJAAQJYhJFMwC1AAAOAAEJXgBDgQAJAAAAAA==.Superuberhot:BAAALgAECgEJAQAAAA==.Superubernot:BAAALgAECgEJAgAAAA==.',
Sy='Syntacks:BAABLgAECn8bAAIQAAgJmBdwTQBOAgAQAAgJmBdwTQBOAgAAAA==.Syzara:BAAALgADCgYJCQAAAA==.',
['Sø']='Sørina:BAAALgAECgEJAQAAAA==.Sørrow:BAABLgAECn8YAAIGAAgJdAuNHAAfAQAGAAgJdAuNHAAfAQAAAA==.',
Ta='Tabi:BAABLgAECn8bAAIQAAgJXQSAKgAiAQAQAAgJXQSAKgAiAQAAAA==.Tacts:BAAALgADCgYJAwAAAA==.Takecare:BAAALgADCgIJAwAAAA==.Tankaa:BAAALgADCgYJBwAAAA==.',
Te='Terein:BAAALgADCgEJAQAAAA==.Test:BAAALgAECgcJDAAAAA==.',
Th='Thedawg:BAAALgADCgEJAQAAAA==.Thedayman:BAAALgAECgYJBgAAAA==.Theo:BAAALgAECgEJAQAAAA==.Therwinn:BAABLgAECn8XAAIBAAYJ2yCXCwCzAQABAAYJ2yCXCwCzAQAAAA==.Thetaint:BAAALgAECgkJDgAAAA==.Thoradin:BAAALgADCgEJAQAAAA==.Thraxion:BAAALgAECgYJDwAAAA==.Thread:BAAALgAECgMJAgAAAA==.Threestorms:BAAALgADCgQJBAAAAA==.Thunderkow:BAAALgADCgcJCAABLgAFFAMJCAAJAEsgAA==.Thunderous:BAAALgAECgMJAwAAAA==.',
Ti='Tinyrunes:BAAALgAECgQJCgAAAA==.',
To='Tojiguro:BAAALgADCgYJBwAAAA==.Tommoorello:BAAALgADCgEJAQAAAA==.Torags:BAAALgADCgEJAgAAAA==.Towfu:BAAALgADCgQJBQAAAA==.',
Tr='Traelayn:BAAALgAECgEJAQAAAA==.Trapgawd:BAAALgADCgEJAQAAAA==.Trentlock:BAABLgAECn8kAAMOAAgJzhj5AgBLAQAJAAUJARixdQByAQAOAAUJiBv5AgBLAQAAAA==.Tristae:BAAALgAECgYJDQAAAA==.Trollslingin:BAAALgADCgkJEAAAAA==.Truuk:BAAALgAECgIJAwAAAA==.',
Tu='Tunapie:BAAALgAECgEJAQAAAA==.',
Ty='Tyzula:BAAALgAECgYJBgAAAA==.',
['Tê']='Têstament:BAAALgAECgQJBAAAAA==.',
Ub='Ubasti:BAAALgAECgYJBwAAAA==.',
Un='Unstablesha:BAAALgADCgkJEgAAAA==.',
Ur='Urahara:BAAALgAECgQJBAAAAA==.',
Va='Valiriel:BAAALgADCgcJDQAAAA==.Varsalis:BAAALgADCgMJAwAAAA==.',
Ve='Velidra:BAAALgADCgYJCQAAAA==.Vellektra:BAAALgAECgEJAQAAAA==.Vernöm:BAAALgAECgQJBAAAAA==.Vethmoree:BAAALgAECgUJBgABLgAECgYJEgAEAAAAAA==.',
Vi='Via:BAAALgAECgUJAQAAAA==.Vil:BAACLgAFFH8VAAIXAAgJIxigAABxAgAXAAgJIxigAABxAgAuAAQKfycAAhcACQk7JtYCAHoDABcACQk7JtYCAHoDAAAA.Vilonus:BAABLgAECn8VAAIJAAYJtg4QHgAsAQAJAAYJtg4QHgAsAQAAAA==.Virvum:BAAALgAECgQJBAAAAA==.',
Vo='Voll:BAAALgAECgQJBQAAAA==.',
Wa='Waxillium:BAAALgAECgQJBAAAAA==.',
We='Werebuddy:BAAALgADCgUJBQAAAA==.Weshyerga:BAAALgADCgYJBgABLgAECggJHAASAHQlAA==.',
Wi='Wigly:BAAALgAECggJDwAAAA==.Willathewise:BAAALgAECgYJBgAAAA==.Wingsolid:BAAALgADCgYJBgAAAA==.Withengar:BAAALgAECgYJCQAAAA==.',
Wr='Wrathrine:BAAALgAECgQJCQAAAA==.',
Wu='Wuoshi:BAAALgAFFAEJAQAAAA==.Wuuzzyy:BAAALgAECgYJBwAAAA==.',
Xa='Xaliko:BAABLgAECn8ZAAMJAAgJYRlICQDcAQAJAAcJChtICQDcAQAOAAYJUxZJEgC6AQAAAA==.Xanathos:BAAALgADCgUJBQAAAA==.Xanbaran:BAABLgAECn8nAAIPAAkJxAkLCACDAQAPAAkJxAkLCACDAQAAAA==.',
Xe='Xena:BAAALgAECgQJBwABLgAECggJIQAkAA0VAA==.',
Xo='Xorellion:BAABLgAECn8XAAIQAAcJWAzjIwBCAQAQAAcJWAzjIwBCAQAAAA==.',
Xy='Xyrters:BAABLgAECn8gAAIFAAgJTyFnBAANAwAFAAgJTyFnBAANAwAAAA==.',
Yi='Yiddiephokin:BAAALgADCgYJCAAAAA==.',
Yu='Yukigodx:BAAALgADCggJEQAAAA==.Yukki:BAAALgAECgEJAQAAAA==.',
Za='Zapmommy:BAAALgADCgIJAgAAAA==.Zariel:BAAALgAECgQJCQAAAA==.Zartini:BAABLgAECn8UAAIGAAYJKxSRHAAfAQAGAAYJKxSRHAAfAQAAAA==.Zaylas:BAAALgADCgMJAwAAAA==.',
Ze='Zeeba:BAAALgADCgEJAQAAAA==.Zerildk:BAAALgAECgYJEgAAAA==.Zerphaine:BAABLgAECn8XAAIIAAgJsQ+0DACIAQAIAAgJsQ+0DACIAQAAAA==.Zevs:BAABLgAECn8VAAIjAAgJdwu4GQBEAQAjAAgJdwu4GQBEAQAAAA==.',
Zi='Zic:BAAALgAECgYJEAAAAA==.Zixxi:BAABLgAECn8gAAIQAAgJgBWoFwCIAQAQAAgJgBWoFwCIAQAAAA==.',
Zu='Zulakar:BAABLgAECn8bAAIdAAYJOxlKNgCjAQAdAAYJOxlKNgCjAQAAAA==.Zurxes:BAAALgAECgcJCwAAAA==.',
Zy='Zynatra:BAAALgAECgEJAQAAAA==.',
['Âk']='Âkaeus:BAABLgAECn8aAAINAAgJXhIyBwCUAQANAAgJXhIyBwCUAQAAAA==.',
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
