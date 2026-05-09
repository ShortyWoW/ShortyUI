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

local lookup = {'Priest-Shadow','DeathKnight-Unholy','Paladin-Protection','Paladin-Retribution','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Havoc','Priest-Holy','Evoker-Augmentation','Unknown-Unknown','Druid-Restoration','Druid-Guardian','Druid-Balance','Druid-Feral','Paladin-Holy','Mage-Frost','Warrior-Protection','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','DemonHunter-Vengeance','Warrior-Fury','Priest-Discipline','Rogue-Subtlety','Shaman-Restoration','Shaman-Elemental','Hunter-BeastMastery','Warlock-Affliction','DemonHunter-Devourer','Mage-Fire','Rogue-Assassination','DeathKnight-Blood','Evoker-Devastation','Mage-Arcane','DeathKnight-Frost','Monk-Brewmaster',}
local provider = {region='US',realm='Goldrinn',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abelao:BAAALgAECgcJEwAAAA==.',
Ad='Adelaide:BAAALgAECgIJAgABLgAFFAcJFQABAAAZAA==.Adoramuss:BAAALgAECgYJCgAAAA==.Adrianoj:BAAALgAECgEJAQAAAA==.',
Ae='Aelon:BAAALgADCgEJAQAAAA==.Aelthor:BAAALgAECgQJBAAAAA==.',
Ah='Ahmus:BAAALgAECgUJDAAAAA==.Ahrallu:BAAALgADCgEJAQAAAA==.',
Ai='Aioliavictus:BAAALgADCgIJAgAAAA==.',
Al='Alanie:BAAALgAECgUJCQAAAA==.Aldranir:BAAALgADCgEJAQAAAA==.Alessaxd:BAABLgAECn8UAAICAAgJfg/TPQCEAQACAAgJfg/TPQCEAQAAAA==.Alexa:BAAALgAECgQJBAAAAA==.Alfajhor:BAABLgAECn8sAAMDAAgJGx1PDgDgAQADAAYJZCBPDgDgAQAEAAgJGxxsNwChAQAAAA==.Alfajhôr:BAAALgAECgUJBgAAAA==.Alkarin:BAAALgAECgEJAQAAAA==.Allandriel:BAAALgAECgQJBAAAAA==.Alldarion:BAAALgAECgMJBgAAAA==.Allendra:BAAALgADCgcJCQAAAA==.Alleriane:BAABLgAECn8oAAMFAAgJhhrGCgA/AgAFAAgJhhrGCgA/AgAGAAEJpwKHjQAYAAAAAA==.Allerios:BAAALgAECgUJCQAAAA==.Allone:BAABLgAECn8VAAIHAAcJxAuCLQBfAQAHAAcJxAuCLQBfAQAAAA==.Allyhra:BAAALgADCgQJBAAAAA==.Allëria:BAAALgADCgMJAwAAAA==.',
Am='Ametnys:BAAALgAECgEJAgAAAA==.Amonhar:BAAALgADCgIJAgABLgAECggJKAAIAP4RAA==.Amyn:BAAALgADCgYJBwAAAA==.',
An='Anakata:BAAALgAECgUJEwAAAA==.Anakinini:BAABLgAECn8WAAIJAAgJmQWYKQAHAQAJAAgJmQWYKQAHAQABLgAECgYJBgAKAAAAAA==.Analia:BAABLgAECn8eAAQLAAgJFR5+HgBLAgALAAcJVR1+HgBLAgAMAAgJlgiFEgDgAAANAAMJQRymOACoAAAAAA==.Andaliz:BAACLgAFFH8JAAIEAAMJ7yGBHQA4AQAEAAMJ7yGBHQA4AQAuAAQKfycAAgQACAkrJUwFAPoCAAQACAkrJUwFAPoCAAAA.Andorith:BAAALgAECgEJAQAAAA==.Anelie:BAAALgAECgQJDAAAAA==.Ansalon:BAAALgADCgYJBwAAAA==.Antonellaes:BAAALgADCgMJAwABLgAECgYJCQAKAAAAAA==.',
Ao='Aoiisuu:BAAALgADCgYJCAAAAA==.',
Ap='Apodrecido:BAAALgAECgYJBgAAAA==.',
Ar='Arajakata:BAAALgAECgEJAgAAAA==.Arctorius:BAAALgAECgQJCgAAAA==.Arlandriah:BAAALgADCgYJCQABLgAECgYJGAAEABAYAA==.Artronis:BAABLgAECn8ZAAMMAAcJRBWeDgAeAQAMAAcJRBWeDgAeAQAOAAEJNRTFJAA/AAAAAA==.Artånis:BAAALgAECgYJCAAAAA==.Aruthuro:BAAALgAECgYJDwAAAA==.',
As='Ashbörn:BAAALgADCgcJDgAAAA==.',
At='Atriuz:BAABLgAECn8bAAIPAAYJaBotLwDGAQAPAAYJaBotLwDGAQAAAA==.Ats:BAAALgADCgYJCgAAAA==.',
Ay='Aykho:BAABLgAECn8nAAIQAAgJQhbkMADdAQAQAAgJQhbkMADdAQAAAA==.',
Az='Azurion:BAAALgAECgQJBAAAAA==.',
['Aÿ']='Aÿ:BAAALgADCgYJBgAAAA==.',
Ba='Baguh:BAAALgADCggJCAAAAA==.Bagunça:BAAALgADCgYJBgAAAA==.Bakuugou:BAAALgAECgMJBgAAAA==.Bambur:BAAALgADCgMJAwAAAA==.Barbabruto:BAABLgAECn8jAAIRAAgJ5Rv7BQA6AgARAAgJ5Rv7BQA6AgAAAA==.Basilisco:BAAALgAECgEJAQAAAA==.',
Be='Belleg:BAAALgAECgEJAQAAAA==.',
Bf='Bf:BAAALgADCgEJAQAAAA==.',
Bi='Biafalcão:BAAALgAECgEJAQAAAA==.Bijanca:BAAALgAECgYJBgAAAA==.Birthdäy:BAAALgADCgEJAQAAAA==.Bisponegro:BAAALgAECgQJBwABLgABCgcJFQAKAAAAAA==.Biønic:BAAALgAECgMJCQAAAA==.',
Bl='Blackline:BAABLgAECn8WAAICAAgJCQ/tPgCAAQACAAgJCQ/tPgCAAQAAAA==.',
Bo='Boipretim:BAAALgAECgQJBwAAAA==.Bontorius:BAAALgADCgEJAQAAAA==.Bordello:BAAALgADCgUJBQAAAA==.',
Br='Bradio:BAAALgADCggJCAAAAA==.Bratloko:BAAALgAECgUJBQAAAA==.Bromos:BAAALgAECgQJCAAAAA==.Brönsted:BAAALgADCgMJAwAAAA==.',
Bu='Bubbalo:BAAALgADCgUJBQAAAA==.Bullsman:BAAALgADCgQJBAAAAA==.Buzzumaaky:BAABLgAECn8YAAIQAAgJSBejiQC/AQAQAAgJSBejiQC/AQAAAA==.',
By='Byakura:BAAALgADCgcJCgAAAA==.',
Ca='Cabernet:BAAALgAECgUJBwAAAA==.Cabeçaquente:BAAALgAECgcJCQAAAA==.Calhistra:BAABLgAECn8nAAMSAAgJQhnKHwDyAQASAAgJQhnKHwDyAQATAAIJRQoeVQBvAAAAAA==.Calteryeker:BAAALgAECgIJAgAAAA==.Camillas:BAAALgAECgUJBgAAAA==.Caosenvy:BAAALgAECgEJAQAAAA==.Caralh:BAAALgAECgEJAgAAAA==.Caroll:BAAALgAECgIJAgAAAA==.Cathe:BAAALgAECgYJEAAAAA==.',
Ce='Cernûnnos:BAAALgAECgUJDwAAAA==.',
Ch='Champdude:BAABLgAECn8mAAIGAAgJzCJbAwDJAgAGAAgJzCJbAwDJAgAAAA==.Chankowkwai:BAAALgAECgYJCQAAAA==.Chanë:BAAALgADCgIJAwAAAA==.',
Ci='Citra:BAAALgAECgMJBwAAAA==.',
Co='Coconolose:BAAALgAECgIJBgAAAA==.Cod:BAAALgAECgIJAwAAAA==.Codecks:BAAALgADCgYJBgAAAA==.Coldhearths:BAAALgAECgUJBgAAAA==.Couro:BAAALgAECgYJCAAAAA==.Cowçadora:BAAALgADCgIJAQAAAA==.',
Cr='Cristcalad:BAABLgAECn8hAAMUAAgJ4hEuCgCjAQAUAAgJ4hEuCgCjAQARAAEJYQUITwAfAAAAAA==.Cryomanta:BAAALgAECgUJBQAAAA==.',
Cu='Cunhaovirado:BAAALgAECgEJAgABLgAFFAQJDAAGANQZAA==.Cunhazinha:BAAALgADCgYJBgAAAA==.Cutia:BAAALgADCgEJAQAAAA==.Cutiesissy:BAAALgAECgQJCAABLgAECgcJGgAEAEkQAA==.',
['Cø']='Cøøkye:BAAALgAECgMJAwAAAA==.',
Da='Daellus:BAAALgADCgUJBQAAAA==.Daemi:BAAALgAECgIJAgAAAA==.Daibodan:BAAALgAECgEJBAAAAA==.Dalaty:BAAALgAECgUJBQAAAA==.Daniilos:BAAALgAECgUJCAAAAA==.Darklara:BAABLgAECn8hAAIVAAgJ3hfVBQCpAQAVAAgJ3hfVBQCpAQAAAA==.Darkove:BAABLgAECn8lAAIQAAkJghAcLADxAQAQAAkJghAcLADxAQAAAA==.Darrow:BAABLgAECn8kAAICAAkJyCL9BAAQAwACAAkJyCL9BAAQAwAAAA==.Dartibeccoso:BAAALgADCgcJBwAAAA==.',
De='Deany:BAAALgADCgcJCAAAAA==.Deathinhu:BAABLgAECn8sAAIQAAkJ3B0cDAC/AgAQAAkJ3B0cDAC/AgAAAA==.Deathnacht:BAAALgAECgMJAwAAAA==.Delset:BAAALgADCgIJAgAAAA==.Demojoca:BAAALgADCgcJDgABLgAECgYJCQAKAAAAAA==.Dentepodre:BAAALgADCgEJAQAAAA==.Dervus:BAAALgADCgcJBwAAAA==.Devrath:BAAALgAECgEJAQAAAA==.Devyogi:BAAALgADCgcJCAAAAA==.',
Di='Dimeros:BAAALgAECggJEwAAAA==.Dito:BAAALgADCgEJAQAAAA==.Divano:BAABLgAECn8XAAIBAAgJARjkDQDrAQABAAgJARjkDQDrAQAAAA==.',
Dk='Dkats:BAAALgAECgEJAgAAAA==.',
Dn='Dng:BAAALgAECgcJCAAAAA==.',
Do='Dogowner:BAAALgAECgcJEAAAAA==.Donora:BAABLgAECn8eAAMEAAgJ0BPGMAC5AQAEAAgJ0BPGMAC5AQADAAEJKgaaOAAaAAAAAA==.',
Dr='Drackmontana:BAABLgAECn8lAAMWAAgJaA4dNgDQAQAWAAgJEQ4dNgDQAQARAAIJEhU+PQBjAAAAAA==.Drafael:BAAALgADCggJDgABLgAECggJKAAOACYhAA==.Dragoniron:BAAALgADCgEJAQAAAA==.Dragony:BAAALgAECgEJAgAAAA==.Dragunass:BAABLgAECn8aAAMRAAcJGRtEEgBAAQAWAAcJHBkBOwC5AQARAAYJeRVEEgBAAQAAAA==.Dragøndeath:BAAALgADCgEJAgAAAA==.Drakars:BAAALgADCgUJBAAAAA==.Drakór:BAAALgADCgQJAQAAAA==.Dranarus:BAAALgADCgQJBAAAAA==.Druidblack:BAAALgAECgIJAgAAAA==.Drunkler:BAAALgAECgEJAQAAAA==.Dryter:BAABLgAECn8VAAIGAAcJEA9JKwCEAQAGAAcJEA9JKwCEAQAAAA==.Drákon:BAAALgADCgIJAgAAAA==.',
Du='Dubhe:BAAALgAECgUJDAAAAA==.',
Dy='Dysttopia:BAAALgADCgcJCAAAAA==.',
El='Eldryrin:BAAALgAECgEJAQAAAA==.Elendile:BAAALgAECgEJAQAAAA==.Elinius:BAABLgAECn8hAAMNAAgJ9x+yBgByAgANAAgJ9x+yBgByAgALAAIJUwytlgAuAAAAAA==.Elistraee:BAAALgADCgcJEAAAAA==.Ellandria:BAAALgAECgMJAgAAAA==.Eloren:BAAALgAECgYJCwABLgAECggJIAAPAO0RAA==.Eluuria:BAAALgAECgkJDQAAAA==.Elyzia:BAAALgAECgEJAQAAAA==.',
En='Endorena:BAAALgADCgEJAQAAAA==.',
Ep='Ephesus:BAAALgADCgIJAgAAAA==.',
Er='Erikssen:BAAALgADCgYJBgAAAA==.Ernest:BAABLgAECn8fAAILAAgJ8RRXJACmAQALAAgJ8RRXJACmAQAAAA==.Erynneus:BAAALgADCgMJAwAAAA==.',
Es='Estagiario:BAAALgAECgIJAQABLgAECggJHAAHAIsfAA==.',
Ev='Evetts:BAAALgADCgEJAQAAAA==.Evilbarba:BAAALgADCgkJEQAAAA==.',
Ex='Exort:BAAALgAECgUJDQAAAA==.Expressão:BAAALgADCgUJBQAAAA==.',
Fa='Faeldar:BAABLgAECn8hAAIXAAgJMRFyDwDbAQAXAAgJMRFyDwDbAQAAAA==.Faldark:BAAALgADCgcJCAAAAA==.Fandrall:BAAALgAECgUJCAAAAA==.Faris:BAAALgAFFAEJAgAAAA==.Faver:BAAALgADCgcJCAAAAA==.Faölin:BAABLgAECn8VAAIYAAcJsRbgDwCnAQAYAAcJsRbgDwCnAQAAAA==.',
Fe='Feenigan:BAAALgAECgEJAQABLgAECgQJBAAKAAAAAA==.Feeniä:BAAALgAECgQJBAAAAA==.Ferael:BAABLgAECn8iAAIEAAkJ0B0ODACiAgAEAAkJ0B0ODACiAgAAAA==.',
Fi='Fil:BAAALgAECgEJAQAAAA==.Firstomega:BAAALgADCgMJAwAAAA==.',
Fl='Flavors:BAABLgAECn8gAAMWAAgJ7SMWAwDiAgAWAAgJ7SMWAwDiAgAUAAQJIR4AFABnAQAAAA==.Florbela:BAAALgAECgUJBQAAAA==.',
Fo='Foxthamy:BAABLgAECn8eAAIFAAcJDRInGwByAQAFAAcJDRInGwByAQAAAA==.',
Fr='Frachlitzz:BAABLgAECn8nAAIQAAgJsROGOwC1AQAQAAgJsROGOwC1AQAAAA==.Fradem:BAAALgADCgIJAQAAAA==.Freccianera:BAAALgADCgEJAQAAAA==.Fredericc:BAABLgAECn8UAAMZAAgJPwoCOgAfAQAZAAcJGAgCOgAfAQAaAAcJjAXFQwCaAAAAAA==.Freyá:BAABLgAECn8XAAIEAAgJmh80DwCDAgAEAAgJmh80DwCDAgAAAA==.Frs:BAAALgAECgEJAgAAAA==.',
Ga='Galhuda:BAAALgADCgYJBgAAAA==.Galyan:BAAALgADCgEJAQAAAA==.Gandwelf:BAAALgADCgkJCQAAAA==.Gazieri:BAABLgAECn8gAAMPAAgJ7RG8KwAyAQAPAAgJ7RG8KwAyAQAEAAQJCw/w2gDWAAAAAA==.',
Gh='Ghalladriel:BAAALgADCgEJAgAAAA==.',
Gi='Giafar:BAAALgAECgEJAQABLgAECgYJBgAKAAAAAA==.',
Gn='Gnomari:BAAALgAECgYJEQAAAA==.',
Go='Gordanado:BAAALgAECgEJAgAAAA==.Gordruida:BAAALgAECgEJAQAAAA==.Govers:BAAALgADCgMJAwABLgAECgMJBAAKAAAAAA==.',
Gr='Greyvor:BAAALgADCgEJAQAAAA==.Grumax:BAABLgAECn8UAAIEAAgJyQ/IdACRAQAEAAgJyQ/IdACRAQAAAA==.Grössa:BAABLgAECn8YAAMPAAcJIwgMOADkAAAPAAcJIwgMOADkAAAEAAMJCQQw6gBDAAABLgAECggJCAAKAAAAAA==.',
Gu='Guitianki:BAAALgAECgEJAQAAAA==.Gulek:BAAALgAECgMJAwAAAA==.Gussg:BAAALgAECggJCAAAAA==.Gustavonz:BAAALgADCgcJBwAAAA==.',
['Gö']='Göhan:BAAALgADCgUJBQABLgAECgYJEwAKAAAAAA==.',
['Gø']='Gøvers:BAAALgAECgMJBAAAAA==.',
Ha='Handyman:BAAALgADCgYJBgAAAA==.',
Hi='Hildegyth:BAABLgAECn8dAAMGAAgJVREuMQBhAQAGAAcJVhEuMQBhAQAFAAUJyAxOLgDiAAAAAA==.',
Hj='Hjalmar:BAAALgADCgcJCQAAAA==.',
Ho='Hodtiva:BAABLgAECn8kAAMBAAgJrg2sHQBOAQABAAgJrg2sHQBOAQAIAAUJ9wrqOgCDAAAAAA==.Homerz:BAAALgADCgEJAQAAAA==.Hotmojo:BAAALgAECgIJAQABLgAECgkJMAAaAMcYAA==.',
Hu='Hunfox:BAACLgAFFH8MAAIbAAMJlBprCwAHAQAbAAMJlBprCwAHAQAuAAQKfy8AAhsACAleIpcJAJwCABsACAleIpcJAJwCAAAA.',
['Hä']='Härkness:BAAALgAECgEJAQAAAA==.',
['Hü']='Hüskar:BAABLgAECn8VAAIWAAgJtQn+IgBYAQAWAAgJtQn+IgBYAQAAAA==.',
Ic='Ichigoz:BAAALgAECggJEQAAAA==.',
Ih='Ihntwuaed:BAAALgADCgYJCQAAAA==.',
Ik='Ikoo:BAABLgAECn8nAAIXAAgJqBudBgCIAgAXAAgJqBudBgCIAgAAAA==.',
Il='Illaril:BAACLgAFFH8PAAIVAAQJHhQbAgASAQAVAAQJHhQbAgASAQAuAAQKf0IAAhUACQnPHmQCANcCABUACQnPHmQCANcCAAAA.',
In='Indarion:BAAALgADCgYJEQAAAA==.Invisiblelol:BAAALgAECgIJAgAAAA==.',
Ir='Irmãodouther:BAAALgAECgUJBQAAAA==.',
Is='Isebby:BAAALgADCgMJAwAAAA==.',
It='Itzzdan:BAAALgADCgMJAwAAAA==.',
Iv='Ivina:BAABLgAECn8UAAMSAAgJTBYXaQD6AAASAAcJTBYXaQD6AAAcAAIJqRe4HACNAAAAAA==.',
Iz='Izaar:BAAALgAECgQJCwAAAA==.',
Ja='Janaìna:BAAALgAECgMJAwAAAA==.Jangeoffry:BAAALgADCgEJAQAAAA==.',
Jh='Jhonatinha:BAABLgAECn8VAAMEAAcJAhkHdQACAQAEAAYJZRkHdQACAQAPAAQJnw64dgCfAAAAAA==.',
Ji='Jigsaww:BAAALgAECgEJAwAAAA==.',
Jo='Joaquim:BAAALgAECgIJAgAAAA==.Jogaveiopl:BAAALgADCgIJAgAAAA==.Joventino:BAAALgADCgQJBQAAAA==.',
Ju='Jucah:BAABLgAECn8WAAIaAAgJwgv7IQBBAQAaAAgJwgv7IQBBAQAAAA==.Jullianxd:BAAALgADCgIJAgABLgAECggJEgAdAIkQAA==.',
Ka='Kaallew:BAABLgAECn8XAAIDAAgJ6BgaDwBHAQADAAgJ6BgaDwBHAQAAAA==.Kaezar:BAAALgADCgEJAQAAAA==.Kainer:BAAALgAECgQJBQAAAA==.Kalazshar:BAAALgAECgUJCQAAAA==.Kalelzinho:BAAALgADCgYJBgAAAA==.Kaluss:BAAALgAECgYJBwAAAA==.Kanalet:BAAALgAECgYJCAAAAA==.Kantaa:BAAALgAECgQJCgAAAA==.Kanturu:BAAALgAECgQJBAAAAA==.Karonn:BAABLgAECn8UAAIEAAYJ9w3mlABTAQAEAAYJ9w3mlABTAQAAAA==.Kavartu:BAAALgADCgUJCAAAAA==.',
Ke='Keillor:BAAALgAECgYJEQAAAA==.Kelantir:BAAALgAECgYJCQABLgAECgcJCgAKAAAAAA==.Keldorian:BAAALgADCgcJEAAAAA==.Kelliar:BAAALgAECgIJAQAAAA==.Kenzou:BAAALgAECgYJCgAAAA==.',
Kh='Khadi:BAAALgAECgYJBgAAAA==.Khaeltaz:BAAALgAECgMJAwAAAA==.Khalandra:BAABLgAECn8ZAAIWAAgJ9BpwKwAIAgAWAAgJ9BpwKwAIAgAAAA==.Khalel:BAAALgADCgEJAgAAAA==.Khaliq:BAABLgAECn8bAAMHAAgJOxaLCgDeAQAHAAgJOxaLCgDeAQAdAAQJLApnrwCtAAAAAA==.Khallani:BAABLgAECn8WAAICAAcJFwhAlQBWAQACAAcJFwhAlQBWAQAAAA==.Khamul:BAAALgAECgIJAgAAAA==.Khaos:BAAALgAECggJEwAAAA==.Khisto:BAABLgAECn8pAAMQAAgJkRqTKgD3AQAQAAgJkRqTKgD3AQAeAAUJsRcbAwBuAQAAAA==.Khroriggs:BAAALgAECgYJDQABLgAECgcJBwAKAAAAAA==.',
Ki='Killerbiie:BAAALgADCgEJAQAAAA==.Killerdown:BAAALgADCgIJAgAAAA==.Kimashi:BAAALgAECgUJBQAAAA==.Kindie:BAAALgADCgcJCwABLgAECggJFAAdAPgHAA==.Kissme:BAAALgAECggJEwAAAA==.Kitamor:BAABLgAECn8rAAINAAkJWgagIAAyAQANAAkJWgagIAAyAQAAAA==.Kiya:BAAALgADCgcJGQAAAA==.',
Ko='Koriakin:BAAALgAECgcJEgAAAA==.Kosmo:BAAALgADCgkJDwAAAA==.Kotalkhan:BAAALgADCgkJEQAAAA==.',
Kr='Krov:BAAALgAECgEJAQAAAA==.Kryon:BAAALgAECgYJDgAAAA==.Kryzthor:BAAALgAECgYJCAAAAA==.Kräsus:BAABLgAECn8oAAIRAAgJNyV/AQD2AgARAAgJNyV/AQD2AgAAAA==.',
Ku='Kul:BAAALgADCgcJCAAAAA==.Kuroelf:BAAALgADCgcJBwAAAA==.Kuthila:BAAALgADCgIJAgAAAA==.',
Ky='Kyzaru:BAAALgAECgEJAQAAAA==.',
['Kÿ']='Kÿdou:BAAALgAECgcJDgAAAA==.',
La='Ladrion:BAABLgAECn8rAAMYAAkJWxqgBwAuAgAYAAkJ/higBwAuAgAfAAgJnhSyAwDvAQAAAA==.Laetus:BAAALgAECgUJEQAAAA==.Lagosta:BAAALgAECgMJBQAAAA==.Laiany:BAABLgAECn8rAAIIAAkJOiCeAgASAwAIAAkJOiCeAgASAwAAAA==.',
Le='Lekrom:BAAALgADCgYJBgAAAA==.Lequinhö:BAAALgAECgIJAgAAAA==.Leric:BAAALgADCgcJCgAAAA==.Lethmar:BAABLgAECn8UAAISAAcJjxGlOgB8AQASAAcJjxGlOgB8AQAAAA==.Leyana:BAAALgAECgUJBQAAAA==.',
Lh='Lhwei:BAAALgAECgIJAgABLgAECggJGwAFAIMVAA==.',
Li='Licaon:BAAALgADCgYJBgAAAA==.Lightbreaker:BAABLgAECn8gAAIEAAgJugd3VQBIAQAEAAgJugd3VQBIAQAAAA==.Lihr:BAAALgADCgYJCQAAAA==.Lilianpotter:BAAALgAECgEJAQAAAA==.Lilithrix:BAAALgADCgIJAgAAAA==.Lillit:BAABLgAECn8hAAQcAAgJSAupBgBIAQAcAAcJgAupBgBIAQASAAcJaQloUgA0AQATAAIJvwZnJABDAAAAAA==.Lindaah:BAABLgAECn8cAAMGAAgJVRVqDwDEAQAGAAgJVRVqDwDEAQAFAAYJtgPiNwCsAAAAAA==.Lindademon:BAAALgAECgMJAwAAAA==.Lindahealer:BAAALgAECgEJAgABLgAECgMJAwAKAAAAAA==.Lislfox:BAABLgAECn8pAAIMAAgJ9hfHBwC2AQAMAAgJ9hfHBwC2AQAAAA==.Lithlad:BAAALgADCgIJAgAAAA==.',
Lk='Lkinho:BAAALgAECgMJBAAAAA==.',
Lm='Lmmds:BAAALgADCgYJBgAAAA==.',
Lo='Lockynha:BAAALgADCgEJAQAAAA==.Loohynir:BAAALgAFFAEJAQAAAA==.Lotusbird:BAAALgADCgcJBwAAAA==.',
Lu='Lukazgplay:BAAALgADCgIJAgAAAA==.Lutsul:BAAALgAECgEJAQAAAA==.',
Ly='Lylka:BAABLgAECn8oAAIDAAgJbCXgAAD1AgADAAgJbCXgAAD1AgAAAA==.Lyrrena:BAAALgAECgMJAwAAAA==.',
Ma='Macumbadora:BAAALgAECgQJCQAAAA==.Madfulock:BAAALgAECgYJCwAAAA==.Maeghann:BAAALgADCgMJAwAAAA==.Magraver:BAAALgADCgUJCAAAAA==.Mais:BAAALgADCgMJBQAAAA==.Malewolyyc:BAABLgAECn8iAAIIAAgJPyNoBQCuAgAIAAgJPyNoBQCuAgAAAA==.Malhun:BAAALgADCgUJDgAAAA==.Malphan:BAAALgAECgcJBwAAAA==.Malyguz:BAACLgAFFH8OAAIQAAQJBhDQMQBFAQAQAAQJBhDQMQBFAQAuAAQKfxkAAhAABwlcG9xgABkCABAABwlcG9xgABkCAAAA.Manipullador:BAAALgAECgIJAgAAAA==.Mapussauro:BAAALgAECgcJDAAAAA==.Maradi:BAAALgADCgIJAgAAAA==.Mariob:BAAALgAECgQJBQAAAA==.Marjøly:BAAALgAECgEJAQAAAA==.Markson:BAAALgADCgEJAQAAAA==.Massafera:BAABLgAECn8cAAIEAAgJgBS1MAC5AQAEAAgJgBS1MAC5AQAAAA==.Mathfacbruxo:BAABLgAECn8nAAISAAgJlhsLFQA5AgASAAgJlhsLFQA5AgAAAA==.Mauritiuz:BAAALgAECgYJCwAAAA==.Mayanyy:BAAALgADCgYJBgAAAA==.',
Mc='Mcq:BAAALgADCgUJBQAAAA==.',
Md='Mdrdark:BAABLgAECn8oAAMCAAkJ2heIKADbAQACAAkJ0heIKADbAQAgAAMJuxVTKQCAAAAAAA==.',
Me='Medz:BAABLgAECn8gAAIQAAgJnBtrHABAAgAQAAgJnBtrHABAAgAAAA==.Meedea:BAAALgADCgUJBgAAAA==.Meetjack:BAAALgADCgIJAgAAAA==.Melania:BAAALgAECgEJAgAAAA==.Melissandra:BAAALgAFFAEJAQAAAA==.Mellkor:BAABLgAECn8hAAIHAAcJtBrhCgDXAQAHAAcJtBrhCgDXAQAAAA==.Melytah:BAAALgAECgEJAgAAAA==.Meraxxes:BAAALgADCgYJBgAAAA==.Merellien:BAAALgADCggJDgAAAA==.Metamorful:BAABLgAECn8UAAILAAgJVhP5SQB7AQALAAgJVhP5SQB7AQAAAA==.',
Mh='Mhorgann:BAAALgADCgcJBwAAAA==.',
Mi='Mijonakombi:BAAALgAECggJDgAAAA==.Milim:BAABLgAECn8dAAMJAAkJIBAuIQA5AQAhAAgJDAt8HgA6AQAJAAkJ2Q4uIQA5AQAAAA==.Milliidan:BAAALgADCgUJBQAAAA==.Mindrathys:BAAALgAECgEJAQAAAA==.Mithrius:BAABLgAECn8UAAIEAAgJaQuBXAA3AQAEAAgJaQuBXAA3AQAAAA==.',
Ml='Mls:BAAALgADCgUJBQAAAA==.',
Mo='Mogrus:BAAALgADCgMJAwAAAA==.Mohanna:BAAALgAECgcJDAAAAA==.Mohanninha:BAAALgAECgYJCwAAAA==.Mohotok:BAABLgAECn8mAAIEAAgJKxnmHwAKAgAEAAgJKxnmHwAKAgAAAA==.Moonøvesso:BAAALgAECgEJAgAAAA==.Moopp:BAAALgADCgIJAgAAAA==.Mortixxia:BAAALgAECgYJEwAAAA==.',
Mu='Muata:BAAALgAECgYJDwAAAA==.Mupar:BAAALgADCgIJAgAAAA==.Murano:BAABLgAECn8nAAMWAAgJyBszCgBEAgAWAAgJyBszCgBEAgAUAAMJywrVJQCZAAAAAA==.Muzzo:BAAALgADCgYJCwABLgAECgUJCQAKAAAAAA==.',
My='Myrmïdom:BAAALgAECgIJAgAAAA==.Myzoreh:BAAALgADCgEJAQAAAA==.',
['Má']='Mágico:BAAALgADCgUJCQAAAA==.Máia:BAAALgAECgYJDQAAAA==.',
['Mä']='Mändosz:BAABLgAECn8WAAICAAgJahKDLQDEAQACAAgJahKDLQDEAQAAAA==.',
['Mé']='Ménace:BAAALgAECggJEgABLgAECggJFAAIAKsRAA==.',
Na='Nalathiel:BAAALgAECgUJBAAAAA==.Narancia:BAAALgAECgEJAgAAAA==.Nassur:BAAALgADCgEJAQAAAA==.Nattaliaa:BAAALgAECgEJAQAAAA==.Nazdru:BAAALgADCgMJAwABLgAECggJKAAOACYhAA==.Nazzh:BAAALgAECgEJAQAAAA==.',
Ne='Necronx:BAAALgAECgEJAQAAAA==.Necronxd:BAAALgADCgEJAgAAAA==.Nefas:BAABLgAECn8dAAITAAkJKhHZAwDcAQATAAkJKhHZAwDcAQAAAA==.Nefazo:BAAALgAECgcJCgAAAA==.Nefilo:BAAALgADCgYJEAAAAA==.Nepthunus:BAABLgAECn8kAAIeAAgJpRiLAQD1AQAeAAgJpRiLAQD1AQAAAA==.Nermand:BAAALgAECgEJAQAAAA==.Neshula:BAAALgADCgMJAwAAAA==.Neuvosor:BAAALgAECgEJAQAAAA==.',
Ni='Nibelunga:BAAALgADCgYJBgAAAA==.Nijor:BAAALgADCgYJBgAAAA==.',
No='Nobelnaga:BAAALgAECgMJAwAAAA==.',
Ny='Nyxra:BAAALgADCgcJEAAAAA==.',
['Nö']='Nöirr:BAAALgADCgUJBQAAAA==.',
Oc='Ocelotte:BAAALgADCgEJAQAAAA==.',
Oi='Oioimiguel:BAAALgADCgUJBQAAAA==.',
Ol='Olhua:BAAALgAECgEJAQAAAA==.Oljedvlad:BAAALgADCgEJAQAAAA==.Oluss:BAAALgADCgUJBQABLgAFFAMJDAAbAJQaAA==.',
Om='Omnath:BAAALgADCgYJBgAAAA==.',
Or='Orillan:BAABLgAECn8oAAMHAAgJ9hahCgDcAQAHAAgJ9hahCgDcAQAdAAEJhAcM5gAsAAAAAA==.Ornsteinsnow:BAABLgAECn8UAAIPAAkJmRGRDwAkAgAPAAkJmRGRDwAkAgAAAA==.Orob:BAAALgAECgEJAQAAAA==.Ororah:BAAALgAECgUJBQAAAA==.Orukam:BAABLgAECn8XAAMLAAgJ6hTqKACKAQALAAgJ6hTqKACKAQANAAIJ5QiJSQBaAAAAAA==.',
Os='Oszwald:BAAALgADCgEJAQAAAA==.',
['Oú']='Oúkürä:BAAALgAECgYJCgAAAA==.',
Pa='Padawani:BAAALgAECgIJAgAAAA==.Padgodeira:BAAALgAECgQJBAAAAA==.Padrealpha:BAAALgADCgcJCgAAAA==.Palaha:BAAALgADCgEJAQABLgAFFAMJDAAbAJQaAA==.Palatina:BAAALgADCgIJAgAAAA==.Panena:BAAALgAECgIJAwAAAA==.Pangedrey:BAABLgAECn8sAAIGAAkJxRsABgB2AgAGAAkJxRsABgB2AgAAAA==.Paracepatrol:BAAALgAECgQJAwAAAA==.Parcival:BAABLgAECn8WAAIbAAkJdhvBEgChAgAbAAkJdhvBEgChAgAAAA==.Parký:BAAALgAECgYJBgAAAA==.Pattalógika:BAAALgAECgEJAQAAAA==.Paullk:BAABLgAECn8WAAINAAYJuBIsIgAnAQANAAYJuBIsIgAnAQAAAA==.',
Pe='Pedrinho:BAAALgADCgYJBgABLgAFFAMJBQAdAFEiAA==.Penéllope:BAAALgAECgEJAQAAAA==.Persëphone:BAAALgAECgYJEAAAAA==.Peruchi:BAAALgAECgQJBAAAAA==.',
Pg='Pgms:BAAALgADCgYJCgAAAA==.',
Ph='Phaxe:BAAALgADCgIJAgAAAA==.Phoenicx:BAAALgADCgMJBgAAAA==.',
Pi='Pipelinebr:BAAALgAECgUJBQAAAA==.',
Pp='Pp:BAAALgAFFAIJAwAAAA==.',
Pr='Prometeus:BAAALgAECgUJCAAAAA==.Pryon:BAAALgAECgUJCwAAAA==.',
['Pä']='Pändero:BAAALgAECgIJBQAAAA==.Pänqueca:BAAALgAECgEJAgAAAA==.',
['Pé']='Pénacova:BAAALgADCgEJAQAAAA==.',
['Pî']='Pîo:BAABLgAECn8XAAMQAAgJYhn8KgD2AQAQAAgJaBj8KgD2AQAiAAQJ0xjuCgArAQAAAA==.',
Qu='Quejerok:BAAALgAECgUJBwAAAA==.',
Ra='Radunz:BAABLgAECn8oAAIOAAgJJiEGAgChAgAOAAgJJiEGAgChAgAAAA==.Raineko:BAAALgADCgYJBgAAAA==.Raio:BAACLgAFFH8FAAIQAAIJkBM9XwCoAAAQAAIJkBM9XwCoAAAuAAQKfyIAAhAACAkLIBAUAHkCABAACAkLIBAUAHkCAAAA.Ralfwur:BAAALgAECgQJBwAAAA==.Rargsa:BAAALgAECgYJDAAAAA==.Rariel:BAAALgADCgMJAgAAAA==.Rasmon:BAABLgAECn8pAAISAAgJ1RRgKADFAQASAAgJ1RRgKADFAQAAAA==.Ravendreth:BAAALgADCgEJAQAAAA==.Raykarla:BAAALgAECgIJAwAAAA==.Raymain:BAABLgAECn8ZAAMGAAkJ8hDvMQBcAQAGAAYJpg/vMQBcAQAFAAcJohSENwANAQAAAA==.Raíka:BAAALgAECgUJBQAAAA==.',
Re='Reddnose:BAAALgAECgUJCQAAAA==.',
Ri='Riesze:BAABLgAECn8UAAIbAAgJdBJsJADEAQAbAAgJdBJsJADEAQAAAA==.',
Ro='Roguinhu:BAAALgAECgEJAQAAAA==.Ropaoo:BAAALgAECgIJBgAAAA==.',
Ru='Rua:BAAALgAECgQJBAAAAA==.Rusga:BAAALgADCgEJAQAAAA==.Rustovick:BAAALgAECgMJBQAAAA==.',
Ry='Rytheas:BAAALgAECgQJBAAAAA==.',
['Rä']='Rämzä:BAAALgAECgYJEwAAAA==.',
['Rå']='Råy:BAAALgAECgQJBQAAAA==.',
Sa='Saargeras:BAAALgADCgMJAwAAAA==.Saffír:BAABLgAECn8XAAIEAAgJaBEKOQCcAQAEAAgJaBEKOQCcAQAAAA==.Saiden:BAAALgADCgQJBAAAAA==.Saintkaue:BAAALgADCgIJAgAAAA==.Samalandraa:BAAALgADCgEJAQAAAA==.Sanahh:BAAALgAECgYJCAAAAA==.Sanateia:BAAALgADCgYJCwAAAA==.Santamadre:BAAALgADCgEJAQAAAA==.Sapekinhä:BAABLgAECn8cAAMHAAgJix+xBgA3AgAHAAcJEyGxBgA3AgAVAAIJQxj5EwCMAAAAAA==.Saphirah:BAAALgADCgEJAQAAAA==.Satanvitória:BAABLgAECn8uAAMUAAgJ7B5NAwByAgAUAAgJbh5NAwByAgAWAAcJYRoxJgAoAgAAAA==.',
Sc='Scheiren:BAAALgAECgMJAwAAAA==.',
Se='Senegos:BAAALgADCgcJBwAAAA==.Sereiaa:BAABLgAECn8XAAIbAAYJTw2MTAAoAQAbAAYJTw2MTAAoAQAAAA==.Sesiom:BAAALgAECgcJBgAAAA==.',
Sh='Shalltearr:BAAALgADCgEJAQAAAA==.Shamate:BAAALgAECgMJAwAAAA==.Shanoa:BAAALgAECgMJAwAAAA==.Sharpersong:BAAALgADCgcJBgAAAA==.Shedo:BAAALgAECggJEwAAAA==.Sheevane:BAABLgAECn8bAAILAAgJGRntGgDsAQALAAgJGRntGgDsAQAAAA==.Shinzo:BAAALgADCgEJAQAAAA==.Shonja:BAAALgADCgcJDgAAAA==.Shula:BAAALgADCgcJDQAAAA==.Shÿnara:BAAALgAECgkJDwAAAA==.',
Si='Siclop:BAAALgADCgYJBgAAAA==.Silgris:BAAALgAECgEJAQABLgAECggJIAAPAO0RAA==.Silmeria:BAAALgAECgcJDQAAAA==.Silverchain:BAAALgADCgcJCgAAAA==.Sinton:BAAALgAECgEJAQAAAA==.',
Sk='Skinme:BAAALgAECgYJDwAAAA==.',
Sm='Smylf:BAAALgAECggJDwAAAA==.',
So='Sombrea:BAAALgAECgMJBgAAAA==.',
Sr='Srheal:BAAALgAECgQJBAAAAA==.Srsapo:BAAALgAECgMJBgAAAA==.',
St='Stampede:BAAALgADCgMJAwAAAA==.Starian:BAABLgAECn8gAAMLAAcJKRxkEwAvAgALAAcJKRxkEwAvAgANAAEJywwLfwAzAAAAAA==.Stëlla:BAABLgAECn8cAAIZAAcJahLPJwCAAQAZAAcJahLPJwCAAQAAAA==.',
Su='Sunnara:BAACLgAFFH8FAAIdAAMJUSK+HwAuAQAdAAMJUSK+HwAuAQAuAAQKfxsAAh0ACQlhIW0UAN0CAB0ACQlhIW0UAN0CAAAA.Superkx:BAAALgAECgQJBQAAAA==.Suzanomu:BAAALgADCgYJCwAAAA==.',
Sy='Sylran:BAAALgADCgQJBgAAAA==.Synk:BAAALgADCgQJBAAAAA==.Syofra:BAAALgAECgQJBQAAAA==.Syrelys:BAAALgADCgYJBgAAAA==.Syuon:BAABLgAECn8bAAIFAAgJgxWnEgDOAQAFAAgJgxWnEgDOAQAAAA==.',
['Së']='Sëkhmet:BAAALgAECgYJCwAAAA==.',
['Sï']='Sïmbä:BAABLgAECn8VAAMCAAgJcQ+cgADfAAACAAgJcQ+cgADfAAAjAAEJkASeGQAoAAAAAA==.',
Ta='Talandar:BAABLgAECn8kAAINAAkJqhILFACiAQANAAkJqhILFACiAQAAAA==.Tankudo:BAAALgAECgYJDwAAAA==.Tanthallas:BAAALgADCggJGQAAAA==.Tavindapedra:BAAALgAECgYJCwAAAA==.',
Tc='Tchutchuco:BAAALgAECgIJAgAAAA==.',
Te='Tekzero:BAAALgAECgEJBgAAAA==.Tempestus:BAAALgADCgYJBgAAAA==.Tennebra:BAAALgADCgYJCAAAAA==.Teobaldo:BAAALgADCgYJCgAAAA==.Terron:BAABLgAECn8fAAIZAAcJiRfKGwDTAQAZAAcJiRfKGwDTAQAAAA==.',
Th='Thabitah:BAABLgAECn8lAAIBAAgJTRrHCQAoAgABAAgJTRrHCQAoAgAAAA==.Thallariel:BAAALgADCggJCAAAAA==.Theteo:BAABLgAECn8WAAIEAAgJfgs9TgBbAQAEAAgJfgs9TgBbAQAAAA==.Thiberios:BAAALgAECgUJDAAAAA==.Thirros:BAAALgADCgUJBQAAAA==.Thorres:BAAALgAECgIJAgAAAA==.Thotamon:BAAALgAECgMJBAAAAA==.Thràain:BAAALgAECgYJCQAAAA==.Thuki:BAAALgADCgYJDAAAAA==.Thunderblade:BAAALgAECgYJDgAAAA==.Théus:BAAALgAECgMJAwABLgAECggJFAAIAKsRAA==.',
Ti='Tiramisu:BAAALgAECgEJAgAAAA==.',
To='Toucinho:BAAALgAECgYJDgAAAA==.',
Tr='Traydd:BAAALgAECgUJDgAAAA==.Trollando:BAAALgADCgkJIAAAAA==.',
Tu='Tuga:BAAALgADCgMJAwAAAA==.Turokk:BAABLgAECn8UAAIbAAgJfA3bLwCOAQAbAAgJfA3bLwCOAQAAAA==.',
Tw='Twilight:BAAALgADCgYJDQAAAA==.Twylluch:BAAALgADCgQJBgABLgAECgkJIwAPAEwWAA==.',
Ul='Ulhim:BAAALgADCgcJEwAAAA==.',
Ur='Uriuri:BAAALgADCgYJBgABLgAECggJKAAOACYhAA==.',
Us='Usfull:BAABLgAECn8oAAMIAAgJ/hFUFQCrAQAIAAgJ/hFUFQCrAQABAAUJkA1QLgDeAAAAAA==.',
Va='Vacavelha:BAAALgAECgEJAQAAAA==.Vahtorn:BAAALgAECgMJBgAAAA==.Valaerys:BAAALgAECgQJBAAAAA==.Valaniri:BAAALgADCgEJAQAAAA==.Vanyathariel:BAAALgADCgYJAwAAAA==.Vareena:BAAALgADCggJCAABLgAECggJKAARADclAA==.Vashiel:BAAALgADCgIJAgAAAA==.',
Ve='Vehuiáh:BAABLgAECn8YAAMPAAgJIxkmFgDdAQAPAAgJIxkmFgDdAQAEAAEJRQQdFwErAAAAAA==.Velen:BAABLgAECn8UAAICAAcJYQ/3VQA8AQACAAcJYQ/3VQA8AQAAAA==.Vellkor:BAAALgADCgYJBgAAAA==.Vellon:BAAALgADCgEJAQAAAA==.Venusa:BAAALgADCgMJBAAAAA==.Verno:BAAALgADCgcJCwAAAA==.Verzuk:BAAALgAECgYJDAAAAA==.',
Vi='Vidnands:BAAALgAECgEJAQAAAA==.Vilthor:BAAALgAECgUJBQAAAA==.Vintekilo:BAABLgAECn8WAAIEAAgJ8BejYgC9AQAEAAgJ8BejYgC9AQAAAA==.',
Vo='Voiddh:BAAALgAECgcJDAAAAA==.Vokeshar:BAAALgADCgUJBQAAAA==.Voltadupla:BAAALgAECgQJBQAAAA==.Voop:BAAALgADCgYJFAAAAA==.',
Vr='Vrenshrrgn:BAAALgADCgYJBgAAAA==.',
Vy='Vygh:BAABLgAECn8gAAMSAAgJkh8EDQCGAgASAAgJkh8EDQCGAgATAAEJIw8wcAA2AAAAAA==.Vyndrill:BAAALgAECgQJBwAAAA==.',
['Vä']='Välion:BAAALgADCgIJAgAAAA==.',
Wa='Wacom:BAAALgADCgUJBQAAAA==.Walkers:BAAALgAECgUJBAAAAA==.Warlaka:BAAALgADCgYJBgAAAA==.Warpiel:BAAALgADCgcJDAABLgAECgkJHgAXACgOAA==.Watchtower:BAAALgADCgYJDgAAAA==.',
Wh='Wheez:BAAALgAECgQJBAABLgAECggJKQAQAJEaAA==.',
Wi='Williem:BAAALgADCgYJEgAAAA==.',
Wo='Worthy:BAAALgADCgQJBAAAAA==.',
Xa='Xafado:BAAALgAECgEJAQAAAA==.Xamalandrö:BAAALgAECgQJCwAAAA==.',
Xe='Xehagus:BAAALgADCgcJCgAAAA==.',
Xi='Xiblaublum:BAAALgADCgMJAwAAAA==.Xiquimiro:BAAALgADCgQJBAAAAA==.',
Xx='Xximperadorx:BAAALgADCgIJAgAAAA==.',
Ya='Yasuoh:BAAALgAECgQJCAAAAA==.',
Ye='Yewner:BAAALgADCgYJBQAAAA==.',
Yi='Yingsu:BAABLgAECn8XAAIkAAgJziAmDQDyAQAkAAgJziAmDQDyAQAAAA==.',
Yo='Yoshihime:BAAALgAECgIJAgABLgAECggJGwALABkZAA==.',
Yv='Yvin:BAAALgAECgMJAwAAAA==.',
Za='Zallmo:BAAALgAECgEJAQAAAA==.Zarath:BAAALgAECgEJAQAAAA==.Zawarudo:BAAALgAECgQJCAAAAA==.',
Ze='Zedd:BAAALgAFFAIJAgAAAA==.Zenorclord:BAAALgADCgQJBgAAAA==.Zeytona:BAABLgAECn8gAAIkAAgJMwwQGgBkAQAkAAgJMwwQGgBkAQAAAA==.',
Zi='Ziracruz:BAAALgAECgQJCwAAAA==.',
['Zí']='Zíngara:BAAALgADCgkJDgAAAA==.',
['Ár']='Árÿä:BAABLgAECn8oAAIbAAgJTxIdKgCoAQAbAAgJTxIdKgCoAQAAAA==.',
['Är']='Äraxy:BAAALgADCgYJEQAAAA==.',
['Äy']='Äy:BAAALgADCgYJCwAAAA==.',
['Ðh']='Ðh:BAAALgADCgkJCQAAAA==.',
['Øl']='Ølokogordo:BAAALgAECgQJBAAAAA==.',
['Øv']='Øvesso:BAAALgAECggJEQAAAA==.',
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
