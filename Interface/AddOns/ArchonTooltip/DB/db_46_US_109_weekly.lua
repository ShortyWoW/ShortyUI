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

local lookup = {'Unknown-Unknown','Paladin-Protection','Paladin-Retribution','Monk-Mistweaver','Monk-Windwalker','Priest-Holy','Druid-Restoration','Druid-Guardian','Paladin-Holy','Mage-Frost','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','Warrior-Protection','DemonHunter-Vengeance','DeathKnight-Unholy','Warrior-Fury','Druid-Feral','Druid-Balance','DemonHunter-Havoc','Priest-Discipline','Priest-Shadow','Hunter-BeastMastery','Warlock-Affliction','Mage-Fire','Rogue-Subtlety','DeathKnight-Blood','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Devourer','Mage-Arcane','Shaman-Restoration','Monk-Brewmaster',}
local provider = {region='US',realm='Goldrinn',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abelao:BAAALgAECgcJEwAAAA==.',
Ad='Adelaide:BAAALgAECgIJAgABLgAECgcJDAABAAAAAA==.Adoramuss:BAAALgAECgYJCQAAAA==.',
Ae='Aelthor:BAAALgADCgkJHQAAAA==.',
Ah='Ahmus:BAAALgAECgUJCAAAAA==.Ahrallu:BAAALgADCgEJAQAAAA==.',
Ai='Aioliavictus:BAAALgADCgIJAgAAAA==.',
Al='Alanie:BAAALgAECgUJCQAAAA==.Aldranir:BAAALgADCgEJAQAAAA==.Alessaxd:BAAALgAECgYJDwAAAA==.Alexa:BAAALgAECgQJBAAAAA==.Alfajhor:BAABLgAECn8rAAMCAAgJcRxQDgDgAQACAAYJYyBQDgDgAQADAAgJWRvsLACOAQAAAA==.Alfajhôr:BAAALgAECgUJBgAAAA==.Allandriel:BAAALgAECgIJAgAAAA==.Alldarion:BAAALgAECgMJBAAAAA==.Allendra:BAAALgADCgcJCQAAAA==.Alleriane:BAABLgAECn8iAAMEAAgJcxQmEACmAQAEAAgJcxQmEACmAQAFAAEJpwKAjQAYAAAAAA==.Allerios:BAAALgADCgMJAwAAAA==.Allone:BAAALgAECgcJEgAAAA==.Allyhra:BAAALgADCgQJBAAAAA==.Allëria:BAAALgADCgMJAwAAAA==.',
Am='Ametnys:BAAALgAECgEJAgAAAA==.Amonhar:BAAALgADCgIJAgABLgAECggJJAAGAP8RAA==.Amyn:BAAALgADCgYJBwAAAA==.',
An='Anakata:BAAALgAECgUJEwAAAA==.Anakinini:BAAALgAECggJDwABLgAECgYJBQABAAAAAA==.Analia:BAABLgAECn8aAAMHAAgJFR5/HgBLAgAHAAcJVR1/HgBLAgAIAAgJlghCDQDkAAAAAA==.Andaliz:BAACLgAFFH8HAAIDAAMJ7iHvEQA+AQADAAMJ7iHvEQA+AQAuAAQKfx8AAgMACAlGI9sFALwCAAMACAlGI9sFALwCAAAA.Andorith:BAAALgAECgEJAQAAAA==.Anelie:BAAALgAECgQJDAAAAA==.Ansalon:BAAALgADCgYJBwAAAA==.Antonellaes:BAAALgADCgMJAwABLgAECgUJCAABAAAAAA==.',
Ao='Aoiisuu:BAAALgADCgYJCAAAAA==.',
Ar='Arajakata:BAAALgADCgQJAQAAAA==.Arctorius:BAAALgAECgQJBwAAAA==.Arlandriah:BAAALgADCgYJCQABLgAECgYJEgABAAAAAA==.Artronis:BAAALgAECgcJEwAAAA==.Artånis:BAAALgAECgYJBgAAAA==.Aruthuro:BAAALgAECgYJDwAAAA==.',
As='Ashbörn:BAAALgADCgcJDgAAAA==.',
At='Atriuz:BAABLgAECn8bAAIJAAYJaBosLwDGAQAJAAYJaBosLwDGAQAAAA==.Ats:BAAALgADCgYJCgAAAA==.',
Ay='Aykho:BAABLgAECn8gAAIKAAgJbBP5KQC8AQAKAAgJbBP5KQC8AQAAAA==.',
Az='Azurion:BAAALgAECgQJBAAAAA==.',
['Aÿ']='Aÿ:BAAALgADCgYJBgAAAA==.',
Ba='Baguh:BAAALgADCggJCAAAAA==.Bagunça:BAAALgADCgYJBgAAAA==.Bakuugou:BAAALgAECgIJAgAAAA==.Bambur:BAAALgADCgMJAwAAAA==.Barbabruto:BAAALgAECgcJDQAAAA==.Basilisco:BAAALgAECgEJAQAAAA==.',
Be='Belleg:BAAALgAECgEJAQAAAA==.',
Bf='Bf:BAAALgADCgEJAQAAAA==.',
Bi='Biafalcão:BAAALgAECgEJAQAAAA==.Bijanca:BAAALgAECgYJBgAAAA==.Bisponegro:BAAALgAECgMJAwABLgABCgcJFQABAAAAAA==.Biønic:BAAALgAECgMJBwAAAA==.',
Bl='Blackline:BAAALgAECgUJDQAAAA==.',
Bo='Boipretim:BAAALgAECgIJAgAAAA==.Bordello:BAAALgADCgUJBQAAAA==.',
Br='Bradio:BAAALgADCggJCAAAAA==.Bratloko:BAAALgAECgUJBQAAAA==.Bromos:BAAALgAECgQJBwAAAA==.Brönsted:BAAALgADCgMJAwAAAA==.',
Bu='Bubbalo:BAAALgADCgUJBQAAAA==.Bullsman:BAAALgADCgQJBAAAAA==.Buzzumaaky:BAABLgAECn8XAAIKAAcJxxipiQC/AQAKAAcJxxipiQC/AQAAAA==.',
By='Byakura:BAAALgADCgYJBgAAAA==.',
Ca='Cabernet:BAAALgAECgUJBwAAAA==.Cabeçaquente:BAAALgAECgcJCQAAAA==.Calhistra:BAABLgAECn8kAAMLAAYJWRx4KgCEAQALAAYJWRx4KgCEAQAMAAIJRQogVQBvAAAAAA==.Calteryeker:BAAALgADCgkJDQAAAA==.Camillas:BAAALgAECgIJAgAAAA==.Caosenvy:BAAALgAECgEJAQAAAA==.Caralh:BAAALgAECgEJAgAAAA==.Caroll:BAAALgAECgIJAgAAAA==.Cathe:BAAALgAECgYJEAAAAA==.',
Ce='Cernûnnos:BAAALgAECgUJCwAAAA==.',
Ch='Champdude:BAABLgAECn8eAAIFAAgJECFUAwCNAgAFAAgJECFUAwCNAgAAAA==.Chankowkwai:BAAALgAECgYJCQAAAA==.Chanë:BAAALgADCgIJAwAAAA==.',
Ci='Citra:BAAALgAECgMJBwAAAA==.',
Co='Coconolose:BAAALgAECgIJBgAAAA==.Cod:BAAALgAECgIJAwAAAA==.Codecks:BAAALgADCgYJBgAAAA==.Coldhearths:BAAALgAECgEJAQAAAA==.Couro:BAAALgAECgYJAgAAAA==.Cowçadora:BAAALgADCgIJAQAAAA==.',
Cr='Cristcalad:BAABLgAECn8ZAAMNAAYJwhG1DAA3AQANAAYJwhG1DAA3AQAOAAEJYQUJTwAfAAAAAA==.Cryomanta:BAAALgAECgUJBQAAAA==.',
Cu='Cunhaovirado:BAAALgAECgEJAQABLgAFFAMJCwAFAFQZAA==.Cunhazinha:BAAALgADCgYJBgABLgAECgYJDQABAAAAAA==.Cutia:BAAALgADCgEJAQAAAA==.Cutiesissy:BAAALgAECgQJCAAAAA==.',
Da='Daellus:BAAALgADCgUJBQAAAA==.Daemi:BAAALgAECgEJAQAAAA==.Daibodan:BAAALgAECgEJBAAAAA==.Dalaty:BAAALgAECgUJBQAAAA==.Daniiboy:BAAALgAECgYJDQAAAA==.Daniilos:BAAALgAECgUJBwAAAA==.Darklara:BAABLgAECn8fAAIPAAgJihaTBACnAQAPAAgJihaTBACnAQAAAA==.Darkove:BAABLgAECn8cAAIKAAgJQg9cgADQAQAKAAgJQg9cgADQAQAAAA==.Darrow:BAABLgAECn8jAAIQAAkJyCJFAgAiAwAQAAkJyCJFAgAiAwAAAA==.Dartibeccoso:BAAALgADCgcJBwAAAA==.',
De='Deany:BAAALgADCgcJBwAAAA==.Deathinhu:BAABLgAECn8jAAIKAAgJASAADQB6AgAKAAgJASAADQB6AgAAAA==.Deathnacht:BAAALgAECgIJAgAAAA==.Delset:BAAALgADCgIJAgAAAA==.Demojoca:BAAALgADCgcJDgABLgAECgUJCAABAAAAAA==.Dentepodre:BAAALgADCgEJAQAAAA==.Dervus:BAAALgADCgcJBwAAAA==.Devyogi:BAAALgADCgcJCAAAAA==.',
Di='Dimeros:BAAALgAECgcJDAAAAA==.Dito:BAAALgADCgEJAQAAAA==.Divano:BAAALgAECgYJDQAAAA==.',
Dk='Dkats:BAAALgAECgEJAgAAAA==.',
Dn='Dng:BAAALgAECgcJCAAAAA==.',
Do='Dogowner:BAAALgAECgYJCgAAAA==.Donora:BAABLgAECn8WAAMDAAgJ/w/VPQBQAQADAAgJ/w/VPQBQAQACAAEJKgbrLAAdAAAAAA==.',
Dr='Drackmontana:BAABLgAECn8lAAMRAAgJaA4eNgDQAQARAAgJEQ4eNgDQAQAOAAIJEhVBPQBjAAAAAA==.Drafael:BAAALgADCggJDgABLgAECggJIAASAAofAA==.Dragoniron:BAAALgADCgEJAQAAAA==.Dragony:BAAALgAECgEJAQAAAA==.Dragunass:BAAALgAECgYJEwAAAA==.Dragøndeath:BAAALgADCgEJAgAAAA==.Drakars:BAAALgADCgUJBAAAAA==.Drakór:BAAALgADCgQJAQAAAA==.Dranarus:BAAALgADCgQJBAAAAA==.Druidblack:BAAALgAECgIJAgAAAA==.Drunkler:BAAALgAECgEJAQAAAA==.Dryter:BAABLgAECn8VAAIFAAcJEA9OKwCEAQAFAAcJEA9OKwCEAQAAAA==.Drákon:BAAALgADCgIJAgAAAA==.',
Du='Dubhe:BAAALgAECgQJBQAAAA==.',
Dy='Dysttopia:BAAALgADCgcJCAAAAA==.',
El='Eldryrin:BAAALgAECgEJAQAAAA==.Elendile:BAAALgAECgEJAQAAAA==.Elinius:BAABLgAECn8aAAMTAAgJQR7cBQBIAgATAAgJQR7cBQBIAgAHAAIJVQyEdwAzAAAAAA==.Elistraee:BAAALgADCgcJEAAAAA==.Ellandria:BAAALgAECgIJAQAAAA==.Eloren:BAAALgAECgYJCwABLgAECggJIAAJAO0RAA==.Eluuria:BAAALgAECgcJDQAAAA==.',
En='Endorena:BAAALgADCgEJAQAAAA==.',
Er='Ernest:BAABLgAECn8fAAIHAAgJ8RSFGQC0AQAHAAgJ8RSFGQC0AQAAAA==.Erynneus:BAAALgADCgMJAwAAAA==.',
Es='Estagiario:BAAALgADCgcJEAABLgAECggJFwAUAMQeAA==.',
Ev='Evetts:BAAALgADCgEJAQAAAA==.Evilbarba:BAAALgADCgkJEQAAAA==.',
Ex='Exort:BAAALgAECgUJDQAAAA==.',
Fa='Faeldar:BAABLgAECn8ZAAIVAAYJ0Q12FQBIAQAVAAYJ0Q12FQBIAQAAAA==.Fandrall:BAAALgAECgUJCAAAAA==.Faris:BAAALgAFFAEJAQAAAA==.Faver:BAAALgADCgcJCAAAAA==.Faölin:BAAALgAECgYJEQAAAA==.',
Fe='Feeniä:BAAALgAECgQJBAAAAA==.Ferael:BAABLgAECn8ZAAIDAAgJkRo5KACEAgADAAgJkRo5KACEAgAAAA==.',
Fi='Firstomega:BAAALgADCgMJAwAAAA==.',
Fl='Flavors:BAABLgAECn8YAAMRAAgJSx5xBQBjAgARAAgJtx1xBQBjAgANAAQJIR4GFABmAQAAAA==.Florbela:BAAALgAECgUJBQAAAA==.',
Fo='Foxthamy:BAABLgAECn8eAAIEAAcJDRK+EwB4AQAEAAcJDRK+EwB4AQAAAA==.',
Fr='Frachlitzz:BAABLgAECn8hAAIKAAgJ3Q9IPAB5AQAKAAgJ3Q9IPAB5AQAAAA==.Fredericc:BAAALgAECggJEgAAAA==.Freezor:BAAALgADCgQJBwAAAA==.Freyá:BAAALgAFFAIJAgAAAA==.Frs:BAAALgAECgEJAgAAAA==.',
Ga='Galhuda:BAAALgADCgYJBgAAAA==.Galyan:BAAALgADCgEJAQAAAA==.Gandwelf:BAAALgADCgkJCQAAAA==.Gazieri:BAABLgAECn8gAAMJAAgJ7RGTIABCAQAJAAgJ7RGTIABCAQADAAQJCw/s2gDWAAAAAA==.',
Gh='Ghalladriel:BAAALgADCgEJAQAAAA==.',
Gi='Giafar:BAAALgAECgEJAQABLgAECgYJBQABAAAAAA==.',
Gn='Gnomari:BAAALgAECgYJCwAAAA==.',
Go='Gordanado:BAAALgAECgEJAgAAAA==.Gordruida:BAAALgAECgEJAQAAAA==.Govers:BAAALgADCgMJAwABLgAECgMJAwABAAAAAA==.',
Gr='Greyvor:BAAALgADCgEJAQAAAA==.Grumax:BAAALgAECgcJEwAAAA==.Grössa:BAAALgAECgcJEgAAAA==.',
Gu='Guitianki:BAAALgADCgEJAgAAAA==.Gulek:BAAALgAECgMJAwAAAA==.Gussg:BAAALgADCgcJCwAAAA==.Gustavonz:BAAALgADCgcJBwAAAA==.',
['Gö']='Göhan:BAAALgADCgUJBQABLgAECgUJEgABAAAAAA==.',
['Gø']='Gøvers:BAAALgAECgMJAwAAAA==.',
Ha='Handyman:BAAALgADCgYJBgAAAA==.',
Hi='Hildegyth:BAABLgAECn8ZAAMFAAYJRRMxMQBhAQAFAAYJRRMxMQBhAQAEAAQJaAv7KQC0AAAAAA==.',
Hj='Hjalmar:BAAALgADCgcJCQAAAA==.',
Ho='Hodtiva:BAABLgAECn8bAAMWAAcJkg39LAB2AQAWAAcJkg39LAB2AQAGAAUJ9wofLwCFAAAAAA==.Homerz:BAAALgADCgEJAQAAAA==.',
Hu='Hunfox:BAACLgAFFH8KAAIXAAMJ8xRrCwAHAQAXAAMJ8xRrCwAHAQAuAAQKfycAAhcACAmKH0ALAOoCABcACAmKH0ALAOoCAAAA.',
['Hä']='Härkness:BAAALgAECgEJAQAAAA==.',
['Hü']='Hüskar:BAAALgAECgUJDQAAAA==.',
Ic='Ichigoz:BAAALgAECgcJCQAAAA==.',
Ih='Ihntwuaed:BAAALgADCgYJCAAAAA==.',
Ik='Ikoo:BAABLgAECn8fAAIVAAgJ8BdPBgBHAgAVAAgJ8BdPBgBHAgAAAA==.',
Il='Illaril:BAACLgAFFH8KAAIPAAMJvBAkAgDBAAAPAAMJvBAkAgDBAAAuAAQKf0AAAg8ACQmzHmQCANcCAA8ACQmzHmQCANcCAAAA.',
In='Indarion:BAAALgADCgYJEQAAAA==.Invisiblelol:BAAALgAECgIJAgAAAA==.',
Ir='Irmãodouther:BAAALgAECgUJBQAAAA==.',
Is='Isebby:BAAALgADCgMJAwAAAA==.',
It='Itzzdan:BAAALgADCgMJAwAAAA==.',
Iv='Ivina:BAABLgAECn8UAAMLAAgJTBYBUAAAAQALAAcJTBYBUAAAAQAYAAIJqRe2HACNAAAAAA==.',
Iz='Izaar:BAAALgAECgQJCwAAAA==.',
Ja='Janaìna:BAAALgAECgMJAwAAAA==.Jangeoffry:BAAALgADCgEJAQAAAA==.',
Jh='Jhonatinha:BAABLgAECn8VAAMDAAcJABkcVgANAQADAAYJZRkcVgANAQAJAAQJnw6xdgCfAAAAAA==.',
Ji='Jigsaww:BAAALgAECgEJAgAAAA==.',
Jo='Joaquim:BAAALgAECgIJAgAAAA==.Jogaveiopl:BAAALgADCgIJAgAAAA==.Joventino:BAAALgADCgQJBQAAAA==.',
Ju='Jucah:BAAALgAECggJDgAAAA==.Jullianxd:BAAALgADCgIJAgABLgAECgYJEwABAAAAAA==.',
Ka='Kaallew:BAABLgAECn8WAAICAAgJpRYPFgBwAQACAAgJpRYPFgBwAQAAAA==.Kaezar:BAAALgADCgEJAQAAAA==.Kainer:BAAALgAECgQJBQAAAA==.Kalazshar:BAAALgAECgUJCQAAAA==.Kalelzinho:BAAALgADCgYJBgAAAA==.Kaluss:BAAALgAECgIJAgAAAA==.Kanalet:BAAALgAECgYJCAAAAA==.Kantaa:BAAALgAECgQJCgAAAA==.Kanturu:BAAALgAECgQJBAAAAA==.Karonn:BAABLgAECn8UAAIDAAYJ9w3olABTAQADAAYJ9w3olABTAQAAAA==.Kavartu:BAAALgADCgUJCAAAAA==.',
Ke='Keillor:BAAALgAECgUJDAAAAA==.Kelantir:BAAALgAECgYJCQABLgAECgcJCgABAAAAAA==.Keldorian:BAAALgADCgcJEAAAAA==.Kelliar:BAAALgAECgIJAQAAAA==.Kenzou:BAAALgAECgQJBAAAAA==.',
Kh='Khadi:BAAALgAECgYJBgAAAA==.Khaeltaz:BAAALgAECgMJAwAAAA==.Khalandra:BAABLgAECn8ZAAIRAAgJ9BpzKwAIAgARAAgJ9BpzKwAIAgAAAA==.Khalel:BAAALgADCgEJAgAAAA==.Khaliq:BAAALgAECgcJEwAAAA==.Khallani:BAABLgAECn8WAAIQAAcJFwg8lQBWAQAQAAcJFwg8lQBWAQAAAA==.Khamul:BAAALgAECgIJAgAAAA==.Khaos:BAAALgAECggJEgAAAA==.Khisto:BAABLgAECn8kAAMKAAcJDBzgKADBAQAKAAcJDBzgKADBAQAZAAEJTBSfBwBJAAAAAA==.Khroriggs:BAAALgAECgYJDQABLgAECgcJBwABAAAAAA==.',
Ki='Killerbiie:BAAALgADCgEJAQAAAA==.Killerdown:BAAALgADCgIJAgAAAA==.Kimashi:BAAALgAECgUJBQAAAA==.Kindie:BAAALgADCgcJCwABLgAECgYJDgABAAAAAA==.Kissme:BAAALgAECggJEwAAAA==.Kitamor:BAABLgAECn8iAAITAAgJqAarHgAHAQATAAgJqAarHgAHAQAAAA==.Kiya:BAAALgADCgcJEwAAAA==.',
Ko='Koriakin:BAAALgAECgUJBgAAAA==.Kosmo:BAAALgADCgkJCQAAAA==.Kotalkhan:BAAALgADCgkJEQAAAA==.',
Kr='Krov:BAAALgADCgEJAQAAAA==.Kryon:BAAALgAECgYJDgAAAA==.Kryzthor:BAAALgAECgYJCAAAAA==.Kräsus:BAABLgAECn8gAAIOAAgJGSKvAQCxAgAOAAgJGSKvAQCxAgAAAA==.',
Ku='Kul:BAAALgADCgcJCAAAAA==.Kuroelf:BAAALgADCgcJBwAAAA==.',
['Kÿ']='Kÿdou:BAAALgAECgcJDgAAAA==.',
La='Ladrion:BAABLgAECn8iAAIaAAgJPhtiBwD8AQAaAAgJPhtiBwD8AQAAAA==.Laetus:BAAALgAECgUJEQAAAA==.Laiany:BAABLgAECn8iAAIGAAgJFR3LEQBTAgAGAAgJFR3LEQBTAgAAAA==.',
Le='Lekrom:BAAALgADCgYJBgAAAA==.Lequinhö:BAAALgAECgIJAgAAAA==.Leric:BAAALgADCgcJCgAAAA==.Lethmar:BAAALgAECgcJDwAAAA==.Leyana:BAAALgAECgUJBQAAAA==.',
Lh='Lhwei:BAAALgAECgIJAgABLgAECggJEwABAAAAAA==.',
Li='Licaon:BAAALgADCgYJBgAAAA==.Lightbreaker:BAABLgAECn8YAAIDAAgJeAUkRwA0AQADAAgJeAUkRwA0AQAAAA==.Lihr:BAAALgADCgYJCQAAAA==.Lilianpotter:BAAALgAECgEJAQAAAA==.Lilithrix:BAAALgADCgIJAgAAAA==.Lillit:BAABLgAECn8ZAAQYAAYJ4AtWBQAyAQAYAAYJJAtWBQAyAQALAAQJYwb62QClAAAMAAIJvwYPHgBDAAAAAA==.Lindaah:BAABLgAECn8WAAMFAAgJUxCkIQDbAAAFAAgJUxCkIQDbAAAEAAYJsgMHKwCvAAAAAA==.Lindademon:BAAALgADCgQJBAABLgAECgEJAQABAAAAAA==.Lindahealer:BAAALgAECgEJAQAAAA==.Lislfox:BAABLgAECn8lAAIIAAgJyBfgBQCkAQAIAAgJyBfgBQCkAQAAAA==.Lithlad:BAAALgADCgIJAgAAAA==.',
Lk='Lkinho:BAAALgAECgMJBAAAAA==.',
Lo='Lockynha:BAAALgADCgEJAQAAAA==.Loohynir:BAAALgAECgcJCAAAAA==.Lotusbird:BAAALgADCgcJBwAAAA==.',
Lu='Lukazgplay:BAAALgADCgIJAgAAAA==.Lutsul:BAAALgAECgEJAQAAAA==.',
Ly='Lylka:BAABLgAECn8gAAICAAgJXCV8AAD2AgACAAgJXCV8AAD2AgAAAA==.Lyrrena:BAAALgAECgMJAwAAAA==.',
Ma='Macumbadora:BAAALgAECgQJBQAAAA==.Madfulock:BAAALgAECgYJCwAAAA==.Maeghann:BAAALgADCgMJAwAAAA==.Magraver:BAAALgADCgUJCAAAAA==.Mais:BAAALgADCgMJBQAAAA==.Malewolyyc:BAABLgAECn8fAAIGAAgJmyJrAwCuAgAGAAgJmyJrAwCuAgAAAA==.Malhun:BAAALgADCgUJCAAAAA==.Malphan:BAAALgAECgcJBwAAAA==.Malyguz:BAACLgAFFH8IAAIKAAMJQg2yMADwAAAKAAMJQg2yMADwAAAuAAQKfxkAAgoABwlcG+hgABkCAAoABwlcG+hgABkCAAAA.Manipullador:BAAALgAECgIJAgAAAA==.Mapussauro:BAAALgADCgUJBQAAAA==.Maradi:BAAALgADCgIJAgAAAA==.Mariob:BAAALgAECgQJBAAAAA==.Markson:BAAALgADCgEJAQAAAA==.Massafera:BAABLgAECn8UAAIDAAgJgRCnMgB4AQADAAgJgRCnMgB4AQAAAA==.Mathfacbruxo:BAABLgAECn8fAAILAAgJvhU7FgD0AQALAAgJvhU7FgD0AQAAAA==.Mauritiuz:BAAALgAECgYJCgAAAA==.Mayanyy:BAAALgADCgYJBgAAAA==.',
Md='Mdrdark:BAABLgAECn8oAAMQAAkJ2hcQGgDsAQAQAAkJ0hcQGgDsAQAbAAMJuxWIHgCCAAAAAA==.',
Me='Medz:BAABLgAECn8YAAIKAAgJURdQHgD2AQAKAAgJURdQHgD2AQAAAA==.Meedea:BAAALgADCgUJBgAAAA==.Meetjack:BAAALgADCgIJAgAAAA==.Melania:BAAALgAECgEJAQAAAA==.Melissandra:BAAALgAFFAEJAQAAAA==.Mellkor:BAABLgAECn8VAAIUAAcJYhf6DABsAQAUAAcJYhf6DABsAQAAAA==.Melytah:BAAALgAECgEJAgAAAA==.Meraxxes:BAAALgADCgUJBQAAAA==.Merellien:BAAALgADCggJCAAAAA==.Metamorful:BAAALgAECgcJEwAAAA==.',
Mh='Mhorgann:BAAALgADCgEJAQAAAA==.',
Mi='Mijonakombi:BAAALgAECgcJDQAAAA==.Milim:BAABLgAECn8UAAMcAAgJjAyMLgBOAQAcAAcJqgmMLgBOAQAdAAcJgguCHgA6AQAAAA==.Milliidan:BAAALgADCgQJBAAAAA==.Mithrius:BAAALgAECgcJDwAAAA==.',
Mo='Mogrus:BAAALgADCgMJAwAAAA==.Mohanna:BAAALgAECgYJBgAAAA==.Mohanninha:BAAALgAECgYJCwAAAA==.Mohotok:BAABLgAECn8eAAIDAAgJDxYBHQDcAQADAAgJDxYBHQDcAQAAAA==.Moonøvesso:BAAALgADCgYJBgAAAA==.Moopp:BAAALgADCgIJAgAAAA==.Mortixxia:BAAALgAECgYJDQAAAA==.',
Mu='Muata:BAAALgAECgYJDwAAAA==.Mupar:BAAALgADCgIJAgAAAA==.Murano:BAABLgAECn8iAAMRAAcJBBW8EgChAQARAAcJBBW8EgChAQANAAMJvAqYGwCdAAAAAA==.Muzzo:BAAALgADCgYJCwAAAA==.',
My='Myrmïdom:BAAALgAECgIJAgAAAA==.',
['Má']='Mágico:BAAALgADCgUJCQAAAA==.Máia:BAAALgAECgYJDQAAAA==.',
['Mä']='Mändosz:BAAALgAECgcJDgAAAA==.',
['Mé']='Ménace:BAAALgAECgcJEQABLgAECggJFAAGAKsRAA==.',
Na='Nalathiel:BAAALgADCgQJBAAAAA==.Narancia:BAAALgAECgEJAgAAAA==.Nassur:BAAALgADCgEJAQAAAA==.Nattaliaa:BAAALgAECgEJAQAAAA==.Nazzh:BAAALgAECgEJAQAAAA==.',
Ne='Necronx:BAAALgADCgkJBwAAAA==.Necronxd:BAAALgADCgEJAgAAAA==.Nefas:BAAALgAECgcJEQAAAA==.Nefazo:BAAALgAECgcJCgAAAA==.Nefilo:BAAALgADCgYJEAAAAA==.Nepthunus:BAABLgAECn8cAAIZAAgJfBcDAQABAgAZAAgJfBcDAQABAgAAAA==.Neshula:BAAALgADCgMJAwAAAA==.Neuvosor:BAAALgAECgEJAQAAAA==.',
Ni='Nibelunga:BAAALgADCgYJBgAAAA==.Nijor:BAAALgADCgYJBgAAAA==.',
No='Nobelnaga:BAAALgAECgMJAwAAAA==.',
Ny='Nyxra:BAAALgADCgcJEAAAAA==.',
Oc='Ocelotte:BAAALgADCgEJAQAAAA==.',
Ol='Olhua:BAAALgAECgEJAQAAAA==.Oljedvlad:BAAALgADCgEJAQAAAA==.Oluss:BAAALgADCgUJBQABLgAFFAMJCgAXAPMUAA==.',
Om='Omnath:BAAALgADCgYJBgAAAA==.',
Or='Orillan:BAABLgAECn8jAAMUAAcJrRGdDAByAQAUAAcJrRGdDAByAQAeAAEJhAcC5gAsAAAAAA==.Ornsteinsnow:BAAALgAECgcJDQAAAA==.Orob:BAAALgAECgEJAQAAAA==.Ororah:BAAALgADCgcJCwAAAA==.Orukam:BAABLgAECn8WAAMHAAgJRhZ9JABfAQAHAAcJRhV9JABfAQATAAIJ5gjROgBaAAAAAA==.',
Os='Oszwald:BAAALgADCgEJAQAAAA==.',
['Oú']='Oúkürä:BAAALgAECgYJCgAAAA==.',
Pa='Padrealpha:BAAALgADCgcJCgAAAA==.Palaha:BAAALgADCgEJAQABLgAFFAMJCgAXAPMUAA==.Palatina:BAAALgADCgIJAgAAAA==.Panena:BAAALgAECgIJAwAAAA==.Pangedrey:BAABLgAECn8jAAIFAAgJHxxMDAC1AgAFAAgJHxxMDAC1AgAAAA==.Paracepatrol:BAAALgAECgQJAwAAAA==.Parcival:BAABLgAECn8UAAIXAAgJ0BrEEgChAgAXAAgJ0BrEEgChAgAAAA==.Pattalógika:BAAALgAECgEJAQAAAA==.Paullk:BAAALgAECgYJEAAAAA==.',
Pe='Pedrinho:BAAALgADCgYJBgABLgAFFAMJBAAeAE4iAA==.Penéllope:BAAALgAECgEJAQAAAA==.Persëphone:BAAALgAECgYJDwAAAA==.Peruchi:BAAALgAECgQJBAAAAA==.',
Pg='Pgms:BAAALgADCgQJBAAAAA==.',
Ph='Phaxe:BAAALgADCgIJAgAAAA==.Phoenicx:BAAALgADCgMJBgAAAA==.',
Pi='Pipelinebr:BAAALgAECgUJBQAAAA==.',
Pp='Pp:BAAALgAECgEJAQAAAA==.',
Pr='Prometeus:BAAALgAECgMJAwAAAA==.Pryon:BAAALgAECgQJBwAAAA==.',
['Pä']='Pändero:BAAALgADCgcJCQAAAA==.Pänqueca:BAAALgAECgEJAgAAAA==.',
['Pé']='Pénacova:BAAALgADCgEJAQAAAA==.',
['Pî']='Pîo:BAABLgAECn8XAAMKAAgJYhmmHAAAAgAKAAgJZximHAAAAgAfAAQJ0xjtCgAsAQAAAA==.',
Qu='Quejerok:BAAALgAECgIJAgAAAA==.',
Ra='Radunz:BAABLgAECn8gAAISAAgJCh/gAQBtAgASAAgJCh/gAQBtAgAAAA==.Raineko:BAAALgADCgYJBgAAAA==.Raio:BAABLgAECn8aAAIKAAgJKhrnGQAQAgAKAAgJKhrnGQAQAgAAAA==.Ralfwur:BAAALgAECgQJBwAAAA==.Rargsa:BAAALgAECgYJCwAAAA==.Rariel:BAAALgADCgMJAgAAAA==.Rasmon:BAABLgAECn8kAAILAAcJyRTmLgBwAQALAAcJyRTmLgBwAQAAAA==.Ravendreth:BAAALgADCgEJAQAAAA==.Raykarla:BAAALgAECgIJAwAAAA==.Raymain:BAABLgAECn8UAAMFAAgJ8gzyMQBcAQAFAAYJuQ3yMQBcAQAEAAYJpxOBNwANAQAAAA==.Raíka:BAAALgADCgcJCwAAAA==.',
Re='Reddnose:BAAALgAECgUJCQAAAA==.',
Ri='Riesze:BAAALgAECgcJDAAAAA==.',
Ro='Ropaoo:BAAALgAECgIJBAAAAA==.',
Ru='Rusga:BAAALgADCgEJAQAAAA==.Rustovick:BAAALgAECgMJBQAAAA==.',
Ry='Rytheas:BAAALgAECgEJAQAAAA==.',
['Rä']='Rämzä:BAAALgAECgUJEgAAAA==.',
['Rå']='Råy:BAAALgAECgQJBQAAAA==.',
Sa='Saargeras:BAAALgADCgMJAwAAAA==.Saffír:BAABLgAECn8XAAIDAAgJaBFMJwCmAQADAAgJaBFMJwCmAQAAAA==.Saiden:BAAALgADCgQJBAAAAA==.Samalandraa:BAAALgADCgEJAQAAAA==.Sanahh:BAAALgAECgIJAgAAAA==.Sanateia:BAAALgADCgYJCwAAAA==.Sapekinhä:BAABLgAECn8XAAMUAAgJxB57EQBTAgAUAAcJKyB7EQBTAgAPAAIJQxj6DwCRAAAAAA==.Saphirah:BAAALgADCgEJAQAAAA==.Satanvitória:BAABLgAECn8mAAMNAAgJth2pAgBKAgANAAgJKRupAgBKAgARAAcJYRowJgAoAgAAAA==.',
Sc='Scheiren:BAAALgAECgMJAwAAAA==.',
Se='Sereiaa:BAAALgAECgYJEQAAAA==.Sesiom:BAAALgAECgcJBgAAAA==.',
Sh='Shalltearr:BAAALgADCgEJAQAAAA==.Shamate:BAAALgAECgIJAgAAAA==.Shanoa:BAAALgAECgMJAwAAAA==.Sharpersong:BAAALgADCgcJBgAAAA==.Shedo:BAAALgAECggJEwAAAA==.Sheevane:BAAALgAECggJEwAAAA==.Shonja:BAAALgADCgcJDgAAAA==.Shula:BAAALgADCgcJDQAAAA==.',
Si='Siclop:BAAALgADCgYJBgAAAA==.Silgris:BAAALgAECgEJAQABLgAECggJIAAJAO0RAA==.Silmeria:BAAALgAECgYJBwAAAA==.Silverchain:BAAALgADCgQJBAAAAA==.Sinton:BAAALgAECgEJAQAAAA==.',
Sk='Skinme:BAAALgAECgYJDwAAAA==.',
Sm='Smylf:BAAALgAECggJDwAAAA==.',
So='Sombrea:BAAALgAECgIJAwAAAA==.',
Sr='Srheal:BAAALgAECgQJBAAAAA==.Srsapo:BAAALgAECgMJBgAAAA==.',
St='Stampede:BAAALgADCgMJAwAAAA==.Starian:BAABLgAECn8bAAMHAAcJKBwgDQA4AgAHAAcJKBwgDQA4AgATAAEJywwEfwAzAAAAAA==.Stëlla:BAAALgAECgUJEQAAAA==.',
Su='Sunnara:BAACLgAFFH8EAAIeAAMJTiKxEQAyAQAeAAMJTiKxEQAyAQAuAAQKfxkAAh4ACAm7H3AUAN0CAB4ACAm7H3AUAN0CAAAA.Superkx:BAAALgAECgQJBQAAAA==.Suzanomu:BAAALgADCgYJCwAAAA==.',
Sy='Sylran:BAAALgADCgQJBgAAAA==.Synk:BAAALgADCgQJBAAAAA==.Syofra:BAAALgAECgQJBQAAAA==.Syrelys:BAAALgADCgYJBgAAAA==.Syuon:BAAALgAECggJEwAAAA==.',
['Së']='Sëkhmet:BAAALgADCgYJBgAAAA==.',
['Sï']='Sïmbä:BAAALgAECgcJEwAAAA==.',
Ta='Talandar:BAABLgAECn8jAAITAAgJ3xM5HwAGAgATAAgJ3xM5HwAGAgAAAA==.Tankudo:BAAALgAECgYJDwAAAA==.Tanthallas:BAAALgADCggJGQAAAA==.Tavinninja:BAAALgAECgUJCQAAAA==.',
Tc='Tchutchuco:BAAALgAECgEJAQAAAA==.',
Te='Tekzero:BAAALgAECgEJBQAAAA==.Tempestus:BAAALgADCgYJBgAAAA==.Tennebra:BAAALgADCgYJCAAAAA==.Teobaldo:BAAALgADCgYJCgAAAA==.Terron:BAABLgAECn8YAAIgAAYJwxgMGAClAQAgAAYJwxgMGAClAQAAAA==.',
Th='Thabitah:BAABLgAECn8dAAIWAAgJ9BctCAAEAgAWAAgJ9BctCAAEAgAAAA==.Thallariel:BAAALgADCggJCAAAAA==.Theteo:BAAALgAECgcJDgAAAA==.Thiberios:BAAALgAECgUJDAAAAA==.Thirros:BAAALgADCgUJBQAAAA==.Thorres:BAAALgAECgIJAgAAAA==.Thotamon:BAAALgAECgMJBAAAAA==.Thràain:BAAALgAECgUJCAAAAA==.Thuki:BAAALgADCgYJDAAAAA==.Thunderblade:BAAALgAECgYJDgAAAA==.Théus:BAAALgAECgMJAwABLgAECggJFAAGAKsRAA==.',
Ti='Tiramisu:BAAALgAECgEJAgAAAA==.',
To='Toucinho:BAAALgAECgYJDgAAAA==.',
Tr='Traydd:BAAALgAECgUJDgAAAA==.Trollando:BAAALgADCggJGAAAAA==.',
Tu='Tuga:BAAALgADCgMJAwAAAA==.Turokk:BAAALgAECgYJDQAAAA==.',
Tw='Twilight:BAAALgADCgYJDQAAAA==.Twylluch:BAAALgADCgQJBgABLgAECggJIgAJAC4YAA==.',
Ul='Ulhim:BAAALgADCgcJEwAAAA==.',
Ur='Uriuri:BAAALgADCgYJBgABLgAECggJIAASAAofAA==.',
Us='Usfull:BAABLgAECn8kAAMGAAgJ/xFaDgC9AQAGAAgJ/xFaDgC9AQAWAAUJiQ08IgDpAAAAAA==.',
Va='Vacavelha:BAAALgAECgEJAQAAAA==.Vahtorn:BAAALgAECgMJBgAAAA==.Valaerys:BAAALgADCgYJBgAAAA==.Vanyathariel:BAAALgADCgYJAwAAAA==.Vareena:BAAALgADCggJCAABLgAECggJIAAOABkiAA==.Vashath:BAAALgADCgcJBwABLgAECgYJEgABAAAAAA==.Vashiel:BAAALgADCgIJAgAAAA==.',
Ve='Vehuiáh:BAAALgAECggJEwAAAA==.Velen:BAAALgAECgYJDQAAAA==.Vellkor:BAAALgADCgYJBgAAAA==.Vellon:BAAALgADCgEJAQAAAA==.Venusa:BAAALgADCgMJBAAAAA==.Verno:BAAALgADCgcJCwAAAA==.Verzuk:BAAALgAECgYJBgAAAA==.',
Vi='Vidnands:BAAALgADCgkJCwAAAA==.Vilthor:BAAALgAECgUJBQAAAA==.Vintekilo:BAABLgAECn8VAAIDAAgJ7xejYgC9AQADAAgJ7xejYgC9AQAAAA==.',
Vo='Voiddh:BAAALgAECgcJDAAAAA==.Vokeshar:BAAALgADCgUJBQAAAA==.Voop:BAAALgADCgYJFAAAAA==.',
Vr='Vrenshrrgn:BAAALgADCgYJBgAAAA==.',
Vy='Vygh:BAABLgAECn8aAAMLAAgJGx/3CAB9AgALAAgJGx/3CAB9AgAMAAEJIw8wcAA2AAAAAA==.Vyndrill:BAAALgAECgMJAwAAAA==.',
['Vä']='Välion:BAAALgADCgIJAgAAAA==.',
Wa='Wacom:BAAALgADCgUJBQAAAA==.Walkers:BAAALgAECgQJAwAAAA==.Warlaka:BAAALgADCgYJBgAAAA==.Warpiel:BAAALgADCgcJDAABLgAECgcJFgAVANUPAA==.Watchtower:BAAALgADCgYJDgAAAA==.',
Wh='Wheez:BAAALgAECgQJBAABLgAECgcJJAAKAAwcAA==.',
Wi='Williem:BAAALgADCgYJDAAAAA==.',
Wo='Worthy:BAAALgADCgQJBAAAAA==.',
Xa='Xamalandrö:BAAALgAECgQJCAAAAA==.',
Xe='Xehagus:BAAALgADCgcJCgAAAA==.',
Xi='Xiquimiro:BAAALgADCgQJBAAAAA==.',
Xx='Xximperadorx:BAAALgADCgIJAgAAAA==.',
Ya='Yasuoh:BAAALgAECgQJBwAAAA==.',
Ye='Yewner:BAAALgADCgYJBQAAAA==.',
Yi='Yingsu:BAABLgAECn8WAAIhAAgJziDoCAAAAgAhAAgJziDoCAAAAgAAAA==.',
Yo='Yoshihime:BAAALgAECgIJAgABLgAECggJEwABAAAAAA==.',
Yv='Yvin:BAAALgADCgIJAgAAAA==.',
Za='Zawarudo:BAAALgAECgQJBAAAAA==.',
Ze='Zedd:BAAALgAFFAIJAgAAAA==.Zenorclord:BAAALgADCgQJBgAAAA==.Zeytona:BAABLgAECn8YAAIhAAgJmAkDFABlAQAhAAgJmAkDFABlAQAAAA==.',
Zi='Ziracruz:BAAALgAECgQJCwAAAA==.',
['Zí']='Zíngara:BAAALgADCgkJDgAAAA==.',
['Ár']='Árÿä:BAABLgAECn8gAAIXAAgJiRGOHQCuAQAXAAgJiRGOHQCuAQAAAA==.',
['Är']='Äraxy:BAAALgADCgYJEQAAAA==.',
['Äy']='Äy:BAAALgADCgYJCwAAAA==.',
['Ðh']='Ðh:BAAALgADCgkJCQAAAA==.',
['Øl']='Ølokogordo:BAAALgAECgEJAQAAAA==.',
['Øv']='Øvesso:BAAALgAECgcJEAAAAA==.',
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
