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

local lookup = {'Paladin-Protection','Paladin-Retribution','Monk-Mistweaver','Monk-Windwalker','Priest-Holy','Unknown-Unknown','Druid-Restoration','Druid-Guardian','Paladin-Holy','Mage-Frost','Warlock-Demonology','Warlock-Destruction','DemonHunter-Vengeance','DeathKnight-Unholy','Warrior-Fury','Warrior-Protection','Druid-Feral','DemonHunter-Havoc','Priest-Shadow','Hunter-BeastMastery','Priest-Discipline','Druid-Balance','Rogue-Subtlety','Warrior-Arms','Mage-Fire','DemonHunter-Devourer','Mage-Arcane','Monk-Brewmaster',}
local provider = {region='US',realm='Goldrinn',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abelao:BAAALgAECgcJEgAAAA==.',
Ad='Adoramuss:BAAALgAECgYJBwAAAA==.',
Ae='Aelthor:BAAALgADCggJHAAAAA==.',
Ah='Ahmus:BAAALgAECgUJCAAAAA==.',
Al='Alanie:BAAALgAECgUJCQAAAA==.Aldranir:BAAALgADCgEJAQAAAA==.Alessaxd:BAAALgAECgQJDAAAAA==.Alfajhor:BAABLgAECn8lAAMBAAgJWhxODgDgAQABAAYJMiBODgDgAQACAAcJzhhsWQDWAQAAAA==.Alfajhôr:BAAALgAECgIJAgAAAA==.Allandriel:BAAALgAECgIJAgAAAA==.Alldarion:BAAALgAECgMJAwAAAA==.Allendra:BAAALgADCgcJCQAAAA==.Alleriane:BAABLgAECn8ZAAMDAAYJrBdACgBJAQADAAYJrBdACgBJAQAEAAEJpwJ7jQAYAAAAAA==.Allerios:BAAALgADCgMJAwAAAA==.Allone:BAAALgAECgcJEQAAAA==.Allyhra:BAAALgADCgQJBAAAAA==.Allëria:BAAALgADCgMJAwAAAA==.',
Am='Ametnys:BAAALgAECgEJAgAAAA==.Amonhar:BAAALgADCgIJAgABLgAECggJHQAFADgQAA==.Amyn:BAAALgADCgYJBwAAAA==.',
An='Anakata:BAAALgAECgQJDQAAAA==.Anakinini:BAAALgAECgYJDAABLgAECgYJBQAGAAAAAA==.Analia:BAABLgAECn8XAAMHAAcJVR19HgBLAgAHAAcJVR19HgBLAgAIAAYJKAoECACxAAAAAA==.Andaliz:BAABLgAECn8XAAICAAgJFSEwEwD5AgACAAgJFSEwEwD5AgAAAA==.Andissa:BAAALgADCgMJAwAAAA==.Andorith:BAAALgAECgEJAQAAAA==.Anelie:BAAALgAECgQJBQAAAA==.Ansalon:BAAALgADCgYJBwAAAA==.',
Ao='Aoiisuu:BAAALgADCgYJCAAAAA==.',
Ar='Arajakata:BAAALgADCgQJAQAAAA==.Arctorius:BAAALgAECgQJBwAAAA==.Arlandriah:BAAALgADCgYJCQABLgAECgYJEgAGAAAAAA==.Artronis:BAAALgAECgYJDQAAAA==.Artånis:BAAALgAECgEJAQAAAA==.Aruthuro:BAAALgAECgYJDwAAAA==.',
As='Ashbörn:BAAALgADCgcJDgAAAA==.',
At='Atriuz:BAABLgAECn8aAAIJAAYJaBpQDAB6AQAJAAYJaBpQDAB6AQAAAA==.Ats:BAAALgADCgYJCgAAAA==.',
Ay='Aykho:BAAALgAECgcJEwAAAA==.',
Az='Azurion:BAAALgAECgQJBAAAAA==.',
['Aÿ']='Aÿ:BAAALgADCgYJBgAAAA==.',
Ba='Baguh:BAAALgADCggJCAAAAA==.Bagunça:BAAALgADCgYJBgAAAA==.Barbabruto:BAAALgAECgcJDQAAAA==.Basilisco:BAAALgAECgEJAQAAAA==.',
Be='Belleg:BAAALgAECgEJAQAAAA==.',
Bf='Bf:BAAALgADCgEJAQAAAA==.',
Bi='Biafalcão:BAAALgADCgUJCAAAAA==.Bijanca:BAAALgAECgYJBgAAAA==.Bisponegro:BAAALgAECgMJAwABLgABCgcJEwAGAAAAAA==.Biønic:BAAALgAECgMJBwAAAA==.',
Bl='Blackline:BAAALgAECgUJBwAAAA==.',
Bo='Boipretim:BAAALgAECgIJAgAAAA==.Bordello:BAAALgADCgUJBQAAAA==.',
Br='Bradio:BAAALgADCggJCAAAAA==.Bratloko:BAAALgADCggJDwAAAA==.Bromos:BAAALgAECgIJAgAAAA==.Brönsted:BAAALgADCgMJAwAAAA==.',
Bu='Bubbalo:BAAALgADCgUJBQAAAA==.Buzzumaaky:BAABLgAECn8WAAIKAAcJaRi9iQC/AQAKAAcJaRi9iQC/AQAAAA==.',
Ca='Cabernet:BAAALgAECgUJBwAAAA==.Cabeçaquente:BAAALgAECgcJCQAAAA==.Calhistra:BAABLgAECn8eAAMLAAYJBhy6TQDfAQALAAYJBhy6TQDfAQAMAAIJRQoXVQBvAAAAAA==.Calteryeker:BAAALgADCgQJBAAAAA==.Camillas:BAAALgADCgUJBQAAAA==.Caosenvy:BAAALgAECgEJAQAAAA==.Cathe:BAAALgAECgYJEAAAAA==.',
Ce='Cernûnnos:BAAALgAECgQJBQAAAA==.',
Ch='Champdude:BAABLgAECn8YAAIEAAgJnB7FAgADAgAEAAgJnB7FAgADAgAAAA==.Chankowkwai:BAAALgAECgYJCQAAAA==.Chanë:BAAALgADCgIJAwAAAA==.',
Ci='Citra:BAAALgADCgQJBQAAAA==.',
Co='Coconolose:BAAALgAECgIJBgAAAA==.Cod:BAAALgAECgIJAgAAAA==.Codecks:BAAALgADCgYJBgAAAA==.',
Cr='Cristcalad:BAAALgAECgYJEwAAAA==.Cryomanta:BAAALgAECgUJBQAAAA==.',
Cu='Cunhaovirado:BAAALgADCgcJCgABLgAFFAMJCAAEAG4UAA==.Cunhazinha:BAAALgADCgYJBgABLgAECgYJCAAGAAAAAA==.Cutia:BAAALgADCgEJAQAAAA==.Cutiesissy:BAAALgAECgQJCAAAAA==.',
Da='Daellus:BAAALgADCgUJBQAAAA==.Daibodan:BAAALgAECgEJAwAAAA==.Dalaty:BAAALgAECgUJBQAAAA==.Daniiboy:BAAALgAECgYJCAAAAA==.Daniilos:BAAALgAECgQJBQAAAA==.Darklara:BAABLgAECn8YAAINAAcJQBbUAgBsAQANAAcJQBbUAgBsAQAAAA==.Darkove:BAABLgAECn8aAAIKAAgJWQ1qgADQAQAKAAgJWQ1qgADQAQAAAA==.Darrow:BAABLgAECn8aAAIOAAgJiSLjDwAeAwAOAAgJiSLjDwAeAwAAAA==.Dartibeccoso:BAAALgADCgcJBwAAAA==.',
De='Deany:BAAALgADCgcJBwAAAA==.Deathinhu:BAABLgAECn8bAAIKAAgJ4R1iLQC8AgAKAAgJ4R1iLQC8AgAAAA==.Deathnacht:BAAALgADCgcJDQAAAA==.Delset:BAAALgADCgIJAgAAAA==.Demojoca:BAAALgADCgcJDgABLgAECgQJBgAGAAAAAA==.Dentepodre:BAAALgADCgEJAQAAAA==.Dervus:BAAALgADCgcJBwAAAA==.Devyogi:BAAALgADCgcJCAAAAA==.',
Di='Dimeros:BAAALgAECgEJAQAAAA==.Dito:BAAALgADCgEJAQAAAA==.Divano:BAAALgAECgYJDAAAAA==.',
Dk='Dkats:BAAALgAECgEJAgAAAA==.',
Dn='Dng:BAAALgAECgcJCAAAAA==.',
Do='Dogowner:BAAALgAECgYJCQAAAA==.Donora:BAAALgAECgYJDgAAAA==.',
Dr='Drackmontana:BAABLgAECn8jAAMPAAgJPw4eNgDQAQAPAAgJ6Q0eNgDQAQAQAAIJEhU7PQBjAAAAAA==.Drafael:BAAALgADCggJDgABLgAECggJGAARALsdAA==.Dragoniron:BAAALgADCgEJAQAAAA==.Dragony:BAAALgADCgMJAwAAAA==.Dragunass:BAAALgAECgYJDQAAAA==.Dragøndeath:BAAALgADCgEJAgAAAA==.Drakars:BAAALgADCgUJBAAAAA==.Drakór:BAAALgADCgQJAQAAAA==.Dranarus:BAAALgADCgQJBAAAAA==.Druidblack:BAAALgAECgIJAgAAAA==.Drunkler:BAAALgADCgQJBAAAAA==.Dryter:BAABLgAECn8VAAIEAAcJEA9KKwCEAQAEAAcJEA9KKwCEAQAAAA==.Drákon:BAAALgADCgIJAgAAAA==.',
Du='Dubhe:BAAALgAECgQJBAAAAA==.',
Dy='Dysttopia:BAAALgADCgcJCAAAAA==.',
El='Eldryrin:BAAALgAECgEJAQAAAA==.Elendile:BAAALgAECgEJAQAAAA==.Elinius:BAAALgAECggJEgAAAA==.Elistraee:BAAALgADCgcJCwAAAA==.Ellandria:BAAALgAECgIJAQAAAA==.Eloren:BAAALgAECgYJCwABLgAECggJIAAJAO0RAA==.Eluuria:BAAALgAECgYJDAAAAA==.',
En='Endorena:BAAALgADCgEJAQAAAA==.',
Er='Ernest:BAABLgAECn8XAAIHAAcJGBPGTQBtAQAHAAcJGBPGTQBtAQAAAA==.Erynneus:BAAALgADCgMJAwAAAA==.',
Es='Estagiario:BAAALgADCgcJEAABLgAECgYJFAASABAiAA==.',
Ev='Evetts:BAAALgADCgEJAQAAAA==.Evilbarba:BAAALgADCgYJCAAAAA==.',
Ex='Exort:BAAALgAECgUJDQAAAA==.',
Fa='Faeldar:BAAALgAECgYJEwAAAA==.Fandrall:BAAALgAECgMJAwAAAA==.Faris:BAAALgAFFAEJAQAAAA==.Faver:BAAALgADCgcJBwAAAA==.Faölin:BAAALgAECgUJDQAAAA==.',
Fe='Feeniä:BAAALgAECgQJBAAAAA==.Ferael:BAABLgAECn8VAAICAAgJnBk7KACEAgACAAgJnBk7KACEAgAAAA==.',
Fi='Firstomega:BAAALgADCgMJAwAAAA==.',
Fl='Flavors:BAAALgAECgcJEwAAAA==.Florbela:BAAALgADCgYJBgAAAA==.',
Fo='Foxthamy:BAAALgAECgYJEwAAAA==.',
Fr='Frachlitzz:BAABLgAECn8ZAAIKAAgJJw5ueADhAQAKAAgJJw5ueADhAQAAAA==.Fredericc:BAAALgAECgcJDgAAAA==.Freezor:BAAALgADCgQJBAAAAA==.Freyá:BAAALgAECgYJCQAAAA==.Frs:BAAALgAECgEJAQAAAA==.',
Ga='Galhuda:BAAALgADCgYJBgAAAA==.Galyan:BAAALgADCgEJAQAAAA==.Gandwelf:BAAALgADCgkJCQAAAA==.Gazieri:BAABLgAECn8gAAMJAAgJ7RH5DgBOAQAJAAgJ7RH5DgBOAQACAAQJCw/v2gDWAAAAAA==.',
Gi='Giafar:BAAALgAECgEJAQABLgAECgYJBQAGAAAAAA==.',
Gn='Gnomari:BAAALgAECgQJBQAAAA==.',
Go='Gordanado:BAAALgADCgcJBwAAAA==.Gordruida:BAAALgAECgEJAQAAAA==.Govers:BAAALgADCgMJAwABLgAECgMJAwAGAAAAAA==.',
Gr='Greyvor:BAAALgADCgEJAQAAAA==.Grumax:BAAALgAECgcJEQAAAA==.Grössa:BAAALgAECgcJEgAAAA==.',
Gu='Guitianki:BAAALgADCgEJAgAAAA==.Gussg:BAAALgADCgQJBAAAAA==.',
['Gö']='Göhan:BAAALgADCgUJBQABLgAECgUJEAAGAAAAAA==.',
['Gø']='Gøvers:BAAALgAECgMJAwAAAA==.',
Ha='Handyman:BAAALgADCgYJBgAAAA==.',
Hi='Hildegyth:BAABLgAECn8VAAIEAAYJRRMwMQBhAQAEAAYJRRMwMQBhAQAAAA==.',
Hj='Hjalmar:BAAALgADCgcJCQAAAA==.',
Ho='Hodtiva:BAABLgAECn8XAAMTAAcJkg33LAB2AQATAAcJkg33LAB2AQAFAAIJLglzcwBaAAAAAA==.Homerz:BAAALgADCgEJAQAAAA==.',
Hu='Hunfox:BAACLgAFFH8JAAIUAAMJRBNkCwAHAQAUAAMJRBNkCwAHAQAuAAQKfx8AAhQACAlEHkELAOoCABQACAlEHkELAOoCAAAA.',
['Hä']='Härkness:BAAALgAECgEJAQAAAA==.',
['Hü']='Hüskar:BAAALgAECgUJDQAAAA==.',
Ic='Ichigoz:BAAALgAECgIJAgAAAA==.',
Ih='Ihntwuaed:BAAALgADCgYJCAAAAA==.',
Ik='Ikoo:BAABLgAECn8XAAIVAAgJFQ0tCABjAQAVAAgJFQ0tCABjAQAAAA==.',
Il='Illaril:BAACLgAFFH8HAAINAAMJUw0lAgDBAAANAAMJUw0lAgDBAAAuAAQKfzYAAg0ACQlvG2UCANcCAA0ACQlvG2UCANcCAAAA.',
In='Indarion:BAAALgADCgYJEQAAAA==.Invisiblelol:BAAALgAECgIJAgAAAA==.',
Is='Isebby:BAAALgADCgMJAwAAAA==.',
It='Itzzdan:BAAALgADCgMJAwAAAA==.',
Iv='Ivina:BAAALgAECgcJEgAAAA==.',
Iz='Izaar:BAAALgAECgEJAQAAAA==.',
Ja='Janaìna:BAAALgAECgMJAwAAAA==.Jangeoffry:BAAALgADCgEJAQAAAA==.',
Jh='Jhonatinha:BAAALgAFFAIJAwAAAA==.',
Jo='Joaquim:BAAALgAECgIJAgAAAA==.Jogaveiopl:BAAALgADCgIJAgAAAA==.Joventino:BAAALgADCgQJBQAAAA==.',
Ju='Jucah:BAAALgAECgcJDAAAAA==.Jullianxd:BAAALgADCgIJAgABLgAECgYJDQAGAAAAAA==.',
Ka='Kaallew:BAABLgAECn8UAAIBAAcJBBcOFgBwAQABAAcJBBcOFgBwAQAAAA==.Kaezar:BAAALgADCgEJAQAAAA==.Kainer:BAAALgAECgEJAQAAAA==.Kalazshar:BAAALgAECgUJCQAAAA==.Kaluss:BAAALgAECgIJAgAAAA==.Kanalet:BAAALgAECgYJCAAAAA==.Kantaa:BAAALgAECgQJCgAAAA==.Karonn:BAAALgAECgYJEgAAAA==.Kavartu:BAAALgADCgUJCAAAAA==.',
Ke='Keillor:BAAALgAECgUJCAAAAA==.Kelantir:BAAALgAECgUJBQABLgAECgcJCgAGAAAAAA==.Keldorian:BAAALgADCgcJEAAAAA==.Kelliar:BAAALgAECgIJAQAAAA==.Kenzou:BAAALgADCgYJBgAAAA==.',
Kh='Khadi:BAAALgAECgYJBgAAAA==.Khaeltaz:BAAALgAECgMJAwAAAA==.Khalandra:BAABLgAECn8XAAIPAAgJ4BlxKwAIAgAPAAgJ4BlxKwAIAgAAAA==.Khalel:BAAALgADCgEJAgAAAA==.Khaliq:BAAALgAECgYJEQAAAA==.Khallani:BAABLgAECn8WAAIOAAcJFwhHlQBWAQAOAAcJFwhHlQBWAQAAAA==.Khaos:BAAALgAECggJEgAAAA==.Khisto:BAABLgAECn8dAAIKAAYJoB2BHABpAQAKAAYJoB2BHABpAQAAAA==.Khroriggs:BAAALgAECgYJDQABLgAECgcJBwAGAAAAAA==.',
Ki='Killerbiie:BAAALgADCgEJAQAAAA==.Killerdown:BAAALgADCgIJAgAAAA==.Kimashi:BAAALgAECgQJBAAAAA==.Kindie:BAAALgADCgcJCwABLgAECgUJCgAGAAAAAA==.Kissme:BAAALgAECgUJCwAAAA==.Kitamor:BAABLgAECn8aAAIWAAgJowbfOgBKAQAWAAgJowbfOgBKAQAAAA==.Kiya:BAAALgADCgcJCgAAAA==.',
Ko='Kotalkhan:BAAALgADCgkJEQAAAA==.',
Kr='Kryon:BAAALgAECgYJDgAAAA==.Kryzthor:BAAALgAECgYJCAAAAA==.Kräsus:BAABLgAECn8YAAIQAAgJviCsAACTAgAQAAgJviCsAACTAgAAAA==.',
Ku='Kul:BAAALgADCgYJBQAAAA==.Kuroelf:BAAALgADCgcJBwAAAA==.',
['Kÿ']='Kÿdou:BAAALgAECgcJDgAAAA==.',
La='Ladrion:BAABLgAECn8aAAIXAAgJ6hSIFABvAgAXAAgJ6hSIFABvAgAAAA==.Laetus:BAAALgAECgUJEQAAAA==.Laiany:BAABLgAECn8aAAIFAAgJaBjFEQBTAgAFAAgJaBjFEQBTAgAAAA==.',
Le='Lekrom:BAAALgADCgYJBgAAAA==.Lequinhö:BAAALgAECgIJAgAAAA==.Leric:BAAALgADCgcJCgAAAA==.Lethmar:BAAALgAECgcJCQAAAA==.Leyana:BAAALgAECgUJBQAAAA==.',
Lh='Lhwei:BAAALgAECgIJAgABLgAECgcJCwAGAAAAAA==.',
Li='Licaon:BAAALgADCgYJBgAAAA==.Lightbreaker:BAAALgAECgcJEgAAAA==.Lihr:BAAALgADCgMJAwAAAA==.Lilianpotter:BAAALgAECgEJAQAAAA==.Lilithrix:BAAALgADCgIJAgAAAA==.Lillit:BAAALgAECgYJEwAAAA==.Lindaah:BAAALgAECgcJDwAAAA==.Lindademon:BAAALgADCgIJAgABLgAECgEJAQAGAAAAAA==.Lindahealer:BAAALgAECgEJAQAAAA==.Lislfox:BAABLgAECn8dAAIIAAgJJxULCwDiAQAIAAgJJxULCwDiAQAAAA==.Lithlad:BAAALgADCgIJAgAAAA==.',
Lk='Lkinho:BAAALgAECgMJAwAAAA==.',
Lo='Lockynha:BAAALgADCgEJAQAAAA==.Loohynir:BAAALgAECgcJCAAAAA==.Lotusbird:BAAALgADCgcJBwAAAA==.',
Lu='Lukazgplay:BAAALgADCgIJAgAAAA==.Lutsul:BAAALgAECgEJAQAAAA==.',
Ly='Lylka:BAABLgAECn8YAAIBAAgJESRPAADJAgABAAgJESRPAADJAgAAAA==.Lyrrena:BAAALgADCgcJEAAAAA==.',
Ma='Macumbadora:BAAALgAECgQJBQAAAA==.Madfulock:BAAALgAECgYJCAAAAA==.Maeghann:BAAALgADCgMJAwAAAA==.Magraver:BAAALgADCgUJCAAAAA==.Mais:BAAALgADCgMJBQAAAA==.Malewolyyc:BAABLgAECn8UAAIFAAcJfx8bDwBvAgAFAAcJfx8bDwBvAgAAAA==.Malhun:BAAALgADCgMJAwAAAA==.Malphan:BAAALgAECgcJBwAAAA==.Malyguz:BAABLgAECn8VAAIKAAcJPhvxYAAZAgAKAAcJPhvxYAAZAgAAAA==.Maradi:BAAALgADCgIJAgAAAA==.Mariob:BAAALgAECgMJAwAAAA==.Markson:BAAALgADCgEJAQAAAA==.Massafera:BAAALgAECgcJEQAAAA==.Mathfacbruxo:BAABLgAECn8XAAILAAgJcBEoEQCIAQALAAgJcBEoEQCIAQAAAA==.Mauritiuz:BAAALgAECgUJBQAAAA==.Mayanyy:BAAALgADCgYJBgAAAA==.',
Md='Mdrdark:BAABLgAECn8iAAIOAAgJdRcoEQCLAQAOAAgJdRcoEQCLAQAAAA==.',
Me='Medz:BAAALgAECgcJEgAAAA==.Meedea:BAAALgADCgUJBgAAAA==.Meetjack:BAAALgADCgIJAgAAAA==.Melania:BAAALgAECgEJAQAAAA==.Melissandra:BAAALgAECgcJBwAAAA==.Mellkor:BAAALgAECgYJDgAAAA==.Meraxxes:BAAALgADCgUJBQAAAA==.Merellien:BAAALgADCggJCAAAAA==.Metamorful:BAAALgAECgcJEwAAAA==.',
Mh='Mhorgann:BAAALgADCgEJAQAAAA==.',
Mi='Mijonakombi:BAAALgAECgEJAgAAAA==.Milim:BAAALgAECggJEwAAAA==.Mithrius:BAAALgAECgYJDQAAAA==.',
Mo='Mogrus:BAAALgADCgMJAwAAAA==.Mohanninha:BAAALgAECgYJCgAAAA==.Mohotok:BAABLgAECn8WAAICAAgJ+RG8EgCMAQACAAgJ+RG8EgCMAQAAAA==.Moopp:BAAALgADCgIJAgAAAA==.Mortixxia:BAAALgADCgYJAgAAAA==.',
Mu='Muata:BAAALgAECgYJDwAAAA==.Mupar:BAAALgADCgIJAgAAAA==.Murano:BAABLgAECn8dAAMPAAYJ4xQySwB4AQAPAAYJZBQySwB4AQAYAAMJvAo1CwCuAAAAAA==.Muzzo:BAAALgADCgYJCwAAAA==.',
My='Myrmïdom:BAAALgADCgYJBgAAAA==.',
['Má']='Mágico:BAAALgADCgUJCQAAAA==.Máia:BAAALgAECgYJDQAAAA==.',
['Mä']='Mändosz:BAAALgAECgYJDAAAAA==.',
['Mé']='Ménace:BAAALgAECgcJEQABLgAECggJEwAGAAAAAA==.',
Na='Narancia:BAAALgAECgEJAgAAAA==.Nassur:BAAALgADCgEJAQAAAA==.Nattaliaa:BAAALgAECgEJAQAAAA==.',
Ne='Necronx:BAAALgADCgkJBwAAAA==.Necronxd:BAAALgADCgEJAgAAAA==.Nefas:BAAALgAECgYJEAAAAA==.Nefazo:BAAALgAECgcJCgAAAA==.Nefilo:BAAALgADCgYJEAAAAA==.Nepthunus:BAABLgAECn8VAAIZAAgJ4xWMAADTAQAZAAgJ4xWMAADTAQAAAA==.Neshula:BAAALgADCgMJAwAAAA==.Neuvosor:BAAALgAECgEJAQAAAA==.',
Ni='Nibelunga:BAAALgADCgYJBgAAAA==.Nijor:BAAALgADCgYJBgAAAA==.',
Ny='Nyxra:BAAALgADCgcJEAAAAA==.',
Oc='Ocelotte:BAAALgADCgEJAQAAAA==.',
Ol='Oljedvlad:BAAALgADCgEJAQAAAA==.Oluss:BAAALgADCgUJBQABLgAFFAMJCQAUAEQTAA==.',
Om='Omeganegro:BAAALgADCgEJAQAAAA==.Omnath:BAAALgADCgYJBgAAAA==.',
Or='Orillan:BAABLgAECn8dAAMSAAYJuRJMBwA8AQASAAYJuRJMBwA8AQAaAAEJhAf85QAsAAAAAA==.Ornsteinsnow:BAAALgAECgQJBAAAAA==.Ororah:BAAALgADCgQJBAAAAA==.Orukam:BAABLgAECn8UAAIHAAcJRhVuDgBvAQAHAAcJRhVuDgBvAQAAAA==.',
Os='Oszwald:BAAALgADCgEJAQAAAA==.',
['Oú']='Oúkürä:BAAALgAECgYJCgAAAA==.',
Pa='Padrealpha:BAAALgADCgcJCgAAAA==.Palaha:BAAALgADCgEJAQABLgAFFAMJCQAUAEQTAA==.Palatina:BAAALgADCgIJAgAAAA==.Panena:BAAALgAECgIJAwAAAA==.Pangedrey:BAABLgAECn8bAAIEAAgJ1RpMDAC1AgAEAAgJ1RpMDAC1AgAAAA==.Paracepatrol:BAAALgADCgYJCgAAAA==.Parcival:BAAALgAECggJEwAAAA==.Paullk:BAAALgAECgUJCQAAAA==.',
Pe='Pedrinho:BAAALgADCgYJBgABLgAECggJGQAaALsfAA==.Penéllope:BAAALgAECgEJAQAAAA==.Persëphone:BAAALgAECgYJDAAAAA==.Peruchi:BAAALgAECgQJBAAAAA==.',
Ph='Phaxe:BAAALgADCgIJAgAAAA==.Phoenicx:BAAALgADCgMJBgAAAA==.',
Pi='Pipelinebr:BAAALgAECgUJBQAAAA==.',
Pp='Pp:BAAALgAECgEJAQAAAA==.',
Pr='Prometeus:BAAALgAECgMJAwAAAA==.Pryon:BAAALgAECgEJAgAAAA==.',
['Pä']='Pändero:BAAALgADCgcJCQAAAA==.Pänqueca:BAAALgAECgEJAQAAAA==.',
['Pé']='Pénacova:BAAALgADCgEJAQAAAA==.',
['Pî']='Pîo:BAABLgAECn8UAAMKAAgJwRjfCQAMAgAKAAgJxhffCQAMAgAbAAQJ0xjsCgAsAQAAAA==.',
Qu='Quejerok:BAAALgADCgkJCQAAAA==.',
Ra='Radunz:BAABLgAECn8YAAIRAAgJux3rAAA6AgARAAgJux3rAAA6AgAAAA==.Raineko:BAAALgADCgYJBgAAAA==.Raio:BAAALgAECgYJEgAAAA==.Ralfwur:BAAALgAECgQJBwAAAA==.Rargsa:BAAALgAECgIJAgAAAA==.Rariel:BAAALgADCgMJAgAAAA==.Rasmon:BAABLgAECn8dAAILAAYJMBWiHAA0AQALAAYJMBWiHAA0AQAAAA==.Ravendreth:BAAALgADCgEJAQAAAA==.Raykarla:BAAALgAECgIJAwAAAA==.Raymain:BAAALgAECggJEgAAAA==.Raíka:BAAALgADCgQJBAAAAA==.',
Re='Reddnose:BAAALgAECgUJCAAAAA==.',
Ri='Riesze:BAAALgAECgUJBQAAAA==.',
Ro='Ropaoo:BAAALgAECgIJAwAAAA==.',
Ru='Rustovick:BAAALgAECgMJBQAAAA==.',
Ry='Rytheas:BAAALgADCgIJAgAAAA==.',
['Rä']='Rämzä:BAAALgAECgUJEAAAAA==.',
['Rå']='Råy:BAAALgAECgQJBQAAAA==.',
Sa='Saargeras:BAAALgADCgMJAwAAAA==.Saffír:BAAALgAECgcJDwAAAA==.Saiden:BAAALgADCgQJBAAAAA==.Sanahh:BAAALgADCgYJCQAAAA==.Sanateia:BAAALgADCgYJCwAAAA==.Sapekinhä:BAABLgAECn8UAAISAAYJECJ7EQBTAgASAAYJECJ7EQBTAgAAAA==.Saphirah:BAAALgADCgEJAQAAAA==.Satanvitória:BAABLgAECn8fAAMYAAgJFxspAQAeAgAPAAcJYRosJgAoAgAYAAgJwRcpAQAeAgAAAA==.',
Sc='Scheiren:BAAALgAECgIJAgAAAA==.',
Se='Sereiaa:BAAALgAECgYJCwAAAA==.',
Sh='Shalltearr:BAAALgADCgEJAQAAAA==.Shanoa:BAAALgAECgMJAwAAAA==.Sharpersong:BAAALgADCgcJBgAAAA==.Shedo:BAAALgAECggJEgAAAA==.Sheevane:BAAALgAECgcJEQAAAA==.Shonja:BAAALgADCgcJDgAAAA==.Shula:BAAALgADCgcJDAAAAA==.',
Si='Siclop:BAAALgADCgYJBgAAAA==.Silgris:BAAALgAECgEJAQABLgAECggJIAAJAO0RAA==.Silmeria:BAAALgAECgEJAQAAAA==.Sinton:BAAALgAECgEJAQAAAA==.',
Sk='Skinme:BAAALgAECgYJDQAAAA==.',
Sm='Smylf:BAAALgAECgcJDQAAAA==.',
So='Sombrea:BAAALgAECgEJAQAAAA==.',
Sr='Srheal:BAAALgAECgQJBAAAAA==.Srsapo:BAAALgAECgMJBgAAAA==.',
St='Stampede:BAAALgADCgMJAwAAAA==.Starian:BAAALgAECgYJEgAAAA==.Stëlla:BAAALgAECgQJDAAAAA==.',
Su='Sunnara:BAABLgAECn8ZAAIaAAgJux9oFADdAgAaAAgJux9oFADdAgAAAA==.Superkx:BAAALgAECgIJAgAAAA==.Suzanomu:BAAALgADCgYJBgAAAA==.',
Sy='Sylran:BAAALgADCgQJBgAAAA==.Synk:BAAALgADCgQJBAAAAA==.Syofra:BAAALgAECgEJAgAAAA==.Syrelys:BAAALgADCgYJBgAAAA==.Syuon:BAAALgAECgcJCwAAAA==.',
['Sï']='Sïmbä:BAAALgAECgcJEwAAAA==.',
Ta='Talandar:BAABLgAECn8bAAIWAAgJrxM7HwAGAgAWAAgJrxM7HwAGAgAAAA==.Tankudo:BAAALgAECgYJDwAAAA==.Tanthallas:BAAALgADCgYJDQAAAA==.Tavinninja:BAAALgAECgUJCQAAAA==.',
Tc='Tchutchuco:BAAALgAECgEJAQAAAA==.',
Te='Tekzero:BAAALgAECgEJAwAAAA==.Tempestus:BAAALgADCgYJBgAAAA==.Tennebra:BAAALgADCgYJCAAAAA==.Teobaldo:BAAALgADCgUJBQAAAA==.Terron:BAAALgAECgYJEgAAAA==.',
Th='Thabitah:BAABLgAECn8VAAITAAgJNRI9BgCiAQATAAgJNRI9BgCiAQAAAA==.Thallariel:BAAALgADCggJCAAAAA==.Theteo:BAAALgAECgcJDgAAAA==.Thiberios:BAAALgAECgUJCwAAAA==.Thorres:BAAALgAECgIJAgAAAA==.Thotamon:BAAALgAECgEJAQAAAA==.Thràain:BAAALgAECgQJBgAAAA==.Thuki:BAAALgADCgYJCgAAAA==.Thunderblade:BAAALgAECgYJDgAAAA==.Théus:BAAALgAECgMJAwABLgAECggJEwAGAAAAAA==.',
Ti='Tiramisu:BAAALgAECgEJAQAAAA==.',
To='Toucinho:BAAALgAECgUJDQAAAA==.',
Tr='Traydd:BAAALgAECgMJCgAAAA==.Trollando:BAAALgADCggJGAAAAA==.',
Tu='Tuga:BAAALgADCgMJAwAAAA==.Turokk:BAAALgAECgYJCwAAAA==.',
Tw='Twilight:BAAALgADCgYJDQAAAA==.Twylluch:BAAALgADCgQJBgABLgAECggJHAAJADsUAA==.',
Ul='Ulhim:BAAALgADCgcJEwAAAA==.',
Ur='Uriuri:BAAALgADCgYJBgABLgAECggJGAARALsdAA==.',
Us='Usfull:BAABLgAECn8dAAMFAAgJOBBDCQBqAQAFAAgJOBBDCQBqAQATAAYJGAf4QQDqAAAAAA==.',
Va='Vacavelha:BAAALgAECgEJAQAAAA==.Vahtorn:BAAALgAECgMJBgAAAA==.Valaerys:BAAALgADCgYJBgAAAA==.Vanyathariel:BAAALgADCgYJAwAAAA==.Vareena:BAAALgADCggJCAABLgAECggJGAAQAL4gAA==.Vashath:BAAALgADCgcJBwABLgAECgYJDQAGAAAAAA==.Vashiel:BAAALgADCgIJAgAAAA==.',
Ve='Vehuiáh:BAAALgAECgcJDwAAAA==.Velen:BAAALgAECgYJCgAAAA==.Vellon:BAAALgADCgEJAQAAAA==.Venusa:BAAALgADCgMJAwAAAA==.Verno:BAAALgADCgcJCwAAAA==.Verzuk:BAAALgADCgYJBgAAAA==.',
Vi='Vidnands:BAAALgADCgkJCgAAAA==.Vintekilo:BAAALgAECgcJEwAAAA==.',
Vo='Voiddh:BAAALgAECgcJDAAAAA==.Vokeshar:BAAALgADCgUJBQAAAA==.Voop:BAAALgADCgYJFAAAAA==.',
Vr='Vrenshrrgn:BAAALgADCgYJBgAAAA==.',
Vy='Vygh:BAAALgAECgYJEgAAAA==.Vyndrill:BAAALgADCgcJBwAAAA==.',
['Vä']='Välion:BAAALgADCgIJAgAAAA==.',
Wa='Wacom:BAAALgADCgUJBQAAAA==.Warpiel:BAAALgADCgcJDAABLgAECgYJDwAGAAAAAA==.Watchtower:BAAALgADCgUJCAAAAA==.',
Wh='Wheez:BAAALgAECgQJBAABLgAECgYJHQAKAKAdAA==.',
Wi='Williem:BAAALgADCgYJBgAAAA==.',
Wo='Worthy:BAAALgADCgQJBAAAAA==.',
Xa='Xamalandrö:BAAALgAECgQJCAAAAA==.',
Xe='Xehagus:BAAALgADCgcJCgAAAA==.',
Xi='Xiquimiro:BAAALgADCgQJBAAAAA==.',
Xx='Xximperadorx:BAAALgADCgIJAgAAAA==.',
Ya='Yasuoh:BAAALgAECgIJAwAAAA==.',
Ye='Yewner:BAAALgADCgYJBQAAAA==.',
Yi='Yingsu:BAABLgAECn8UAAIcAAcJnyDGEwByAgAcAAcJnyDGEwByAgAAAA==.',
Yv='Yvin:BAAALgADCgIJAgAAAA==.',
Za='Zawarudo:BAAALgAECgQJBAAAAA==.',
Ze='Zedd:BAAALgAECgYJBwAAAA==.Zenorclord:BAAALgADCgQJBgAAAA==.Zeytona:BAAALgAECgcJEgAAAA==.',
Zi='Ziracruz:BAAALgAECgQJCwAAAA==.',
['Zí']='Zíngara:BAAALgADCgcJDAAAAA==.',
['Ár']='Árÿä:BAABLgAECn8YAAIUAAgJYRAuDwCKAQAUAAgJYRAuDwCKAQAAAA==.',
['Är']='Äraxy:BAAALgADCgYJDwAAAA==.',
['Äy']='Äy:BAAALgADCgMJBQAAAA==.',
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
