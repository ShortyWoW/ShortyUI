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

local lookup = {'Shaman-Restoration','Shaman-Elemental','DemonHunter-Devourer','Unknown-Unknown','Evoker-Augmentation','Evoker-Preservation','Paladin-Protection','Druid-Restoration','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Protection','Druid-Balance','DeathKnight-Unholy','Paladin-Retribution','Druid-Feral','Evoker-Devastation','DemonHunter-Havoc','Shaman-Enhancement','Warrior-Fury','Priest-Shadow','Druid-Guardian','Rogue-Subtlety','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','Hunter-Survival','Warlock-Demonology','Warlock-Destruction','Mage-Frost','Mage-Arcane','Priest-Holy','Paladin-Holy','Mage-Fire','Warlock-Affliction','DeathKnight-Blood','Rogue-Outlaw','DeathKnight-Frost',}
local provider = {region='US',realm='Eonar',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abbazaad:BAAALgAECgQJBQAAAA==.Abreen:BAAALgADCgcJCQAAAA==.Abysseus:BAAALgADCgcJCAAAAA==.',
Ac='Acepriest:BAAALgAECgEJAQAAAA==.Achievement:BAAALgAECgQJBAAAAA==.',
Ad='Adeathfox:BAAALgADCgEJAQAAAA==.Admired:BAAALgAECgcJEwAAAA==.Adyr:BAABLgAECn8fAAMBAAgJlB+WCQBRAgABAAgJlB+WCQBRAgACAAUJtxdATQATAQAAAA==.',
Ai='Aidra:BAAALgAECgQJEQAAAA==.',
Al='Alaira:BAAALgAECgMJAwAAAA==.Alamora:BAAALgAECgMJAwAAAA==.Alastair:BAAALgAECgcJCAAAAA==.Alathena:BAAALgAECgUJBQAAAA==.Albinoz:BAAALgADCgIJAgAAAA==.Albrect:BAAALgADCgYJEQAAAA==.Aldrich:BAAALgADCgEJAQAAAA==.Alexandrya:BAAALgAFFAEJAQAAAA==.Alicemalkin:BAABLgAECn8WAAIDAAgJKRXvPQD8AQADAAgJKRXvPQD8AQAAAA==.Alysse:BAAALgADCgUJBwAAAA==.',
Am='Amarysia:BAAALgAECgYJCQAAAA==.Ameriixs:BAAALgAECgIJAgAAAA==.Amsip:BAAALgAECgEJAQABLgAECgYJEQAEAAAAAA==.Amsroeb:BAAALgAECgYJEQAAAA==.',
An='Anelavenger:BAACLgAFFH8HAAIFAAMJpw5vGADmAAAFAAMJpw5vGADmAAAuAAQKfy0AAwUACQnYHMsMAKkCAAUACQnYHMsMAKkCAAYAAwlaAStEAE0AAAAA.',
Ao='Aomori:BAAALgAECgcJBwAAAA==.',
Aq='Aqüilés:BAAALgAECgEJAQAAAA==.',
Ar='Arathor:BAABLgAECn8VAAIHAAYJgxuZDwDLAQAHAAYJgxuZDwDLAQAAAA==.Arctorius:BAAALgADCgEJAQAAAA==.Arent:BAABLgAECn8iAAIIAAgJ4BFSHwCGAQAIAAgJ4BFSHwCGAQAAAA==.Arfy:BAAALgADCgMJAgABLgAECgYJDQAEAAAAAA==.Argøn:BAABLgAECn8dAAMJAAgJKBehHQCuAQAJAAgJKBehHQCuAQAKAAEJkAYBkgAoAAAAAA==.Arkanna:BAAALgAECgEJAQAAAA==.Arrise:BAAALgAECgMJBAAAAA==.Artemislives:BAAALgAECgcJBAAAAA==.Arthuaca:BAAALgAECgYJDQAAAA==.',
As='Asharia:BAAALgAECgYJDQAAAA==.Ashog:BAAALgADCgUJBQAAAA==.Assateague:BAAALgAECgMJAwAAAA==.Astralie:BAAALgADCgcJCAAAAA==.Asuya:BAAALgADCgYJCQAAAA==.',
At='Atrosity:BAABLgAECn8iAAILAAgJ0yK+AQCtAgALAAgJ0yK+AQCtAgAAAA==.',
Au='Aurorabane:BAAALgADCgUJBQAAAA==.',
Av='Avelleah:BAAALgAECgEJBAAAAA==.',
Az='Azulyne:BAAALgADCgIJAgAAAA==.Azuretorrent:BAAALgADCgQJBAAAAA==.',
Ba='Bananapistol:BAAALgAECgUJBQAAAA==.Barrathfrogy:BAAALgADCgUJBwAAAA==.',
Be='Bertelo:BAAALgADCgUJBQAAAA==.',
Bi='Bigstinky:BAAALgAECgEJAQAAAA==.Bisao:BAAALgAECgIJAgAAAA==.Biscuít:BAABLgAECn8nAAIMAAkJDQ7pDgCiAQAMAAkJDQ7pDgCiAQAAAA==.',
Bl='Blasuoff:BAAALgADCgEJAQAAAA==.Bloodrains:BAAALgAECgEJAwAAAA==.Bloodyfate:BAAALgADCgUJBQAAAA==.',
Bo='Bonesentinel:BAAALgAECgYJBwABLgAFFAQJBgANAP0XAA==.Bonës:BAAALgADCgEJAQAAAA==.Bora:BAAALgAECgQJDgAAAA==.Borzoi:BAABLgAFFH8IAAIOAAMJKhzsGQAQAQAOAAMJKhzsGQAQAQAAAA==.Bourgùîgnon:BAAALgADCgcJCgAAAA==.',
Br='Bragasch:BAAALgADCgkJGQAAAA==.Brakhon:BAAALgAECgEJAQAAAA==.Bruisebrews:BAAALgADCgEJAQAAAA==.',
Bu='Bullplop:BAAALgADCgUJBQAAAA==.Burekbazino:BAAALgADCgcJCQAAAA==.',
['Bò']='Bò:BAABLgAECn8lAAIMAAkJ4hAGCgDvAQAMAAkJ4hAGCgDvAQAAAA==.',
Ca='Caduceus:BAAALgADCgcJEgAAAA==.Caesus:BAAALgAECgYJDAAAAA==.Cagedancer:BAABLgAECn8WAAMPAAYJZAcOEgC4AAAPAAYJ4QMOEgC4AAAMAAYJxQZWLACtAAAAAA==.Callio:BAABLgAECn8mAAIJAAkJIRBZEwD3AQAJAAkJIRBZEwD3AQAAAA==.Cantor:BAAALgAECgEJAQAAAA==.Catchclause:BAAALgADCgkJFAAAAA==.Cathillex:BAAALgAECgYJDQAAAA==.Cavagos:BAABLgAECn8vAAIQAAkJvx5dAADwAgAQAAkJvx5dAADwAgAAAA==.Caycay:BAACLgAFFH8KAAIRAAQJzB6UAgBmAQARAAQJzB6UAgBmAQAuAAQKfzgAAhEACQljJfEAAL4DABEACQljJfEAAL4DAAAA.',
Ce='Celebrexi:BAAALgAECgcJBgAAAA==.Celene:BAAALgADCgYJBwAAAA==.Cerrulli:BAAALgAECgYJDgAAAA==.',
Ch='Chaosknight:BAAALgAECgUJDAAAAA==.Chaostrip:BAABLgAECn8iAAIDAAgJUiL7BACVAgADAAgJUiL7BACVAgABLgAECgYJGgADAK8aAA==.Chillbros:BAACLgAFFH8KAAISAAQJGR/LAQAJAQASAAQJGR/LAQAJAQAuAAQKfyIAAxIACAmOJPkBADwDABIACAkQJPkBADwDAAIABAmqH+k5AGcBAAAA.Chillmage:BAAALgADCgcJCgABLgAFFAQJCgASABkfAA==.Chindi:BAABLgAECn8fAAITAAgJLBQyDgDRAQATAAgJLBQyDgDRAQAAAA==.Choiminasue:BAAALgAECgEJAgAAAA==.Chunga:BAABLgAECn8UAAICAAYJoAPNXADQAAACAAYJoAPNXADQAAAAAA==.Chungers:BAAALgAECgQJBgAAAA==.Churd:BAABLgAECn8lAAIUAAgJcRjgBgAeAgAUAAgJcRjgBgAeAgAAAA==.Churdicus:BAAALgADCgkJEQAAAA==.Chypper:BAAALgADCgEJAQAAAA==.Chypster:BAAALgAECgQJDgAAAA==.',
Ci='Ciceroe:BAAALgAECgYJBgAAAA==.Citadel:BAAALgADCgIJAwAAAA==.',
Cl='Cleft:BAAALgAECgMJBAAAAA==.',
Co='Coalystra:BAABLgAECn8jAAIDAAkJdxpsBwBkAgADAAkJdxpsBwBkAgAAAA==.Cocopuffs:BAACLgAFFH8HAAIMAAIJrxEAFwChAAAMAAIJrxEAFwChAAAuAAQKfy4AAgwACQlIICEJAAMDAAwACQlIICEJAAMDAAAA.Colostrom:BAABLgAECn8mAAIHAAkJuh3GAgBPAgAHAAkJuh3GAgBPAgAAAA==.Complicatedz:BAAALgAECgQJBAAAAA==.Comul:BAAALgADCgcJBwAAAA==.Coramage:BAAALgAECgYJEAAAAA==.Corentis:BAAALgADCgYJBgAAAA==.Corliss:BAAALgAECgYJDQAAAA==.',
Cp='Cplusmc:BAAALgADCgYJBgAAAA==.',
Cr='Creightizle:BAABLgAECn8eAAIJAAgJdxS4OQDHAQAJAAgJdxS4OQDHAQAAAA==.',
['Cá']='Cátix:BAAALgADCgEJAQAAAA==.',
Da='Daicmerollin:BAAALgAECgYJBgAAAA==.Danhaüsen:BAAALgAECgIJAwAAAA==.Darkbeast:BAAALgADCgcJBwABLgAECgcJGAAOAD8TAA==.Darkdeeds:BAAALgADCggJCgAAAA==.Darkpallo:BAABLgAECn8YAAIOAAcJPxPXbwCdAQAOAAcJPxPXbwCdAQAAAA==.Daten:BAABLgAECn8pAAIOAAkJ9hFxLgCIAQAOAAkJ9hFxLgCIAQAAAA==.Dazshauran:BAAALgADCgEJAQAAAA==.Daîma:BAAALgADCggJCAAAAA==.',
De='Deathbycow:BAABLgAECn8dAAIVAAgJDxnqAwD1AQAVAAgJDxnqAwD1AQAAAA==.Decayed:BAAALgAECgYJEAAAAA==.Demonchalk:BAAALgAFFAEJAQABLgAFFAMJCgASAH0kAA==.Dewbie:BAAALgAECgEJAQAAAA==.',
Di='Diagonalli:BAAALgAECgYJEQAAAA==.Dimmadome:BAAALgADCgEJAQAAAA==.Dinojam:BAAALgADCgMJAQAAAA==.Divirian:BAAALgAECgQJCAAAAA==.',
Dj='Djdaemon:BAAALgADCgYJBgAAAA==.Djpaly:BAAALgADCgQJBAAAAA==.Djpriest:BAAALgADCgYJBwAAAA==.Djshadowhunt:BAAALgADCgYJDQAAAA==.Djshadowlock:BAAALgADCgUJBgAAAA==.Djshadowrog:BAAALgADCgUJBQAAAA==.Djshaolin:BAAALgADCgUJBwAAAA==.Djzhadow:BAAALgADCgMJAwAAAA==.Djzhadruid:BAAALgADCgQJBAAAAA==.',
Dm='Dmitrì:BAAALgADCgEJAQAAAA==.',
Do='Dogno:BAAALgADCgEJAQAAAA==.Dontdieplez:BAAALgAECgcJCAAAAA==.',
Dp='Dpm:BAAALgAECgEJAgAAAA==.',
Dr='Dragbuttakis:BAAALgAECgUJCAAAAA==.Drakmon:BAAALgADCgUJBQAAAA==.Draktând:BAABLgAECn8XAAIWAAgJcQ1DDAClAQAWAAgJcQ1DDAClAQAAAA==.Drippysilk:BAAALgAECgQJCAABLgAECgYJGgAQAPwiAA==.Drius:BAAALgADCgMJAwAAAA==.Drunkenpanda:BAABLgAECn8ZAAMXAAcJEBYSJQCKAQAXAAcJEBYSJQCKAQAYAAYJqwcyLACcAAAAAA==.Drunknoodle:BAAALgAECgQJBQAAAA==.',
Du='Duhpriest:BAAALgAECgEJAQAAAA==.Duinrane:BAAALgAECgEJAQAAAA==.Duon:BAAALgAECgcJDwAAAA==.',
Dw='Dwagonfur:BAAALgAECgcJBgAAAA==.',
Ec='Echö:BAABLgAECn8bAAIRAAgJIhZtBwDfAQARAAgJIhZtBwDfAQAAAA==.',
Ei='Eirø:BAAALgADCgkJCQABLgAECgkJKQAKAPkhAA==.',
El='Elaine:BAAALgAECgYJCgAAAA==.Elberon:BAAALgAECgIJAgAAAA==.Elmerhomero:BAAALgADCgUJBQAAAA==.Elronnd:BAAALgADCgkJFwAAAA==.Elsebeth:BAAALgADCgcJCAAAAA==.',
Em='Emilie:BAAALgADCgYJBgAAAA==.',
En='Enoch:BAABLgAECn8bAAIOAAYJjRZXfwB7AQAOAAYJjRZXfwB7AQAAAA==.',
Er='Eriam:BAAALgADCgEJAQABLgAECgYJDQAEAAAAAA==.Errane:BAACLgAFFH8MAAIIAAQJPhweCAB+AQAIAAQJPhweCAB+AQAuAAQKfycAAwgACAnJJo0EAEYDAAgACAnJJo0EAEYDAAwAAQnHFUh4AEQAAAAA.Eruiluvatar:BAAALgAECgYJBgAAAA==.',
Et='Etalia:BAAALgADCgUJBQAAAA==.Etcetera:BAAALgADCgYJBwAAAA==.',
Fa='Fallenangell:BAAALgADCgUJBQAAAA==.Fandiirn:BAAALgADCgYJBgAAAA==.Fastjack:BAAALgAECgQJDwAAAA==.',
Fi='Fiora:BAAALgADCgYJCwAAAA==.Fistoffury:BAABLgAECn8WAAMZAAYJPxStHgAMAQAZAAYJPxStHgAMAQAYAAQJOAn6WQCoAAAAAA==.Fitco:BAAALgADCgYJCwABLgAECgYJDwAEAAAAAA==.Fiènd:BAAALgADCgYJBgAAAA==.',
Fl='Flametar:BAAALgAECgEJAQAAAA==.Floppydisk:BAAALgAECgUJCwAAAA==.',
Fo='Fortiss:BAABLgAECn8bAAMBAAkJRgggJgA7AQABAAkJRgggJgA7AQACAAMJxATXOgB+AAAAAA==.',
Fr='Frito:BAAALgAECgEJAQAAAA==.Frost:BAAALgAFFAIJAgABLgAFFAYJEwAaAFMSAA==.Frostmon:BAAALgAECgYJDAAAAA==.Frshnvrfrzn:BAAALgAECggJDwAAAA==.Frøzenblight:BAAALgAECgEJAQAAAA==.',
Fu='Fulmo:BAAALgADCgUJBQABLgAECggJFQANABENAA==.Furbee:BAAALgAECgcJCAAAAA==.',
['Fá']='Fáde:BAAALgADCgQJBQABLgAECgMJAwAEAAAAAA==.',
Ga='Galeandra:BAAALgAECgQJBQAAAA==.Garim:BAAALgADCgEJAQABLgAECgQJDwAEAAAAAA==.',
Ge='Geraltofrvia:BAAALgAECgYJCgAAAA==.',
Gi='Giantgoose:BAAALgAECgEJAgAAAA==.Gingani:BAAALgADCgcJBwAAAA==.',
Gn='Gnar:BAAALgAECgQJBwAAAA==.',
Go='Gowtherdead:BAAALgADCgQJBAAAAA==.Gowtherpunch:BAABLgAECn8oAAIZAAkJKBNPCQD5AQAZAAkJKBNPCQD5AQAAAA==.',
Gr='Gregzug:BAAALgADCgkJCQAAAA==.Greyjoy:BAAALgADCgYJBQAAAA==.Grimsy:BAAALgADCgYJBwAAAA==.Grodd:BAAALgADCgUJBQAAAA==.Groqqu:BAAALgAECgQJBAAAAA==.Grumble:BAAALgAECgIJAgAAAA==.Gruxxiron:BAAALgAECgUJBgABLgAECggJJwANAN8dAA==.',
Gu='Gulnn:BAABLgAECn8jAAMbAAgJQhzzCwBVAgAbAAgJQhzzCwBVAgAcAAIJVhT4VABvAAAAAA==.',
Ha='Haelena:BAAALgAECgUJDAAAAA==.Halys:BAAALgADCgUJBQAAAA==.Hamil:BAAALgADCgEJAQAAAA==.Hawk:BAAALgADCgYJBgAAAA==.',
He='Helfire:BAAALgADCgYJBgABLgAECgMJAwAEAAAAAA==.Hellscreems:BAAALgADCgMJAwAAAA==.Heriotza:BAABLgAECn8VAAINAAgJEQ1ZbACyAQANAAgJEQ1ZbACyAQAAAA==.',
Ia='Iamfubar:BAAALgADCgMJAwAAAA==.',
Ig='Igris:BAAALgAECgcJCAAAAA==.',
Ii='Iimit:BAAALgAECggJEgAAAA==.',
Il='Illidead:BAACLgAFFH8OAAIdAAYJ7RkABwDGAQAdAAYJ7RkABwDGAQAuAAQKfxsAAx0ACAldISs7AIoCAB0ACAkcHis7AIoCAB4AAQnXHxYXAGEAAAAA.',
Im='Implied:BAAALgADCgUJBQAAAA==.',
In='Indexes:BAAALgAECgIJAgAAAA==.Insrik:BAAALgAECgEJAwAAAA==.',
Io='Iompróirbáis:BAABLgAECn8XAAINAAgJsgZGOQBVAQANAAgJsgZGOQBVAQAAAA==.',
Ir='Irdeadohnoz:BAAALgAECgQJCQAAAA==.',
Is='Ist:BAAALgAECgEJAQAAAA==.',
It='Itchigo:BAAALgAECgYJCQAAAA==.',
Iv='Ivern:BAAALgAECgIJAgAAAA==.Ivgorod:BAAALgAECgYJEgAAAA==.',
Ja='Jambi:BAAALgAECgYJDgAAAA==.Jardani:BAAALgAECgEJAQAAAA==.Jastrae:BAAALgAECgcJDgAAAA==.Jazilyne:BAAALgADCgkJFwAAAA==.',
Je='Jealous:BAAALgADCgUJBQABLgAECgkJIgADAKMdAA==.Jenka:BAAALgAECgQJCQAAAA==.',
Ji='Jibbs:BAAALgADCgkJCQAAAA==.',
Jo='Joleya:BAAALgADCgEJAQAAAA==.',
Ju='Junta:BAAALgADCgcJHwAAAA==.Justine:BAAALgADCgUJBQAAAA==.Justtrolling:BAAALgAECgYJDgAAAA==.',
['Jä']='Jäkel:BAAALgADCgUJBQAAAA==.',
Ka='Kambative:BAAALgAECgcJEwABLgAECgkJLQAFAGEgAA==.Kammunion:BAAALgADCgMJAwABLgAECgkJLQAFAGEgAA==.Kamphiyer:BAABLgAECn8tAAQFAAkJYSCvBgAwAgAFAAcJpyCvBgAwAgAGAAgJaBmZBAAmAgAQAAMJFwu7MQCIAAAAAA==.Kamscendance:BAAALgADCgMJAwABLgAECgkJLQAFAGEgAA==.Kamsumerage:BAAALgADCgkJEgABLgAECgkJLQAFAGEgAA==.Kandosii:BAAALgADCgUJBQAAAA==.Kantheal:BAAALgAECgYJEgAAAA==.Kaulana:BAAALgADCgcJCwAAAA==.',
Ke='Keirmania:BAAALgADCgQJBwAAAA==.Kellendere:BAAALgADCgYJBgAAAA==.',
Ki='Kiieedk:BAAALgAECgEJAQAAAA==.Kimgoeun:BAAALgADCgYJBgAAAA==.Kio:BAAALgAECgYJCAAAAA==.',
Kn='Knùsê:BAAALgADCgUJBgABLgAECgkJKQAKAPkhAA==.',
Ko='Komorai:BAAALgADCgYJBgAAAA==.',
Kr='Kravex:BAAALgAECgYJDQAAAA==.Krixxa:BAABLgAECn8fAAIfAAgJsSKxAgDQAgAfAAgJsSKxAgDQAgAAAA==.',
['Kä']='Kären:BAAALgAECgUJEgAAAA==.',
['Ké']='Kélly:BAAALgAECgcJCAAAAA==.',
La='Larayvia:BAABLgAECn8dAAIJAAgJIw4/OwDBAQAJAAgJIw4/OwDBAQAAAA==.Laurance:BAAALgADCgYJBgAAAA==.',
Le='Leesala:BAABLgAECn8nAAMBAAkJeRbaCgA8AgABAAkJeRbaCgA8AgASAAEJ0QRxGgAxAAAAAA==.Lerazer:BAAALgAECgMJAwAAAA==.',
Lg='Lgidk:BAAALgADCgMJAwABLgAECgkJIgADAKMdAA==.',
Li='Lic:BAAALgADCgkJGAAAAA==.Liliatrix:BAAALgAECgQJBAAAAA==.Lillabet:BAAALgADCggJEgAAAA==.Lilsneaky:BAAALgADCggJCAAAAA==.Limpydk:BAAALgADCgUJBQABLgAECgYJGgAQAPwiAA==.Limpylarva:BAAALgADCgMJAwABLgAECgYJGgAQAPwiAA==.Limpypal:BAAALgAECgEJAQABLgAECgYJGgAQAPwiAA==.Litter:BAAALgAECgUJBQAAAA==.',
Lo='Logathil:BAAALgAECgYJEAAAAA==.',
Lu='Luchulainn:BAAALgADCgYJBgAAAA==.Lucifero:BAAALgAECgUJBwAAAA==.Lucifurwild:BAAALgADCgQJBQAAAA==.Lunaaris:BAABLgAECn8rAAIIAAkJCB8dBADsAgAIAAkJCB8dBADsAgAAAA==.Lunastre:BAAALgADCgEJAQAAAA==.',
['Lí']='Límpy:BAABLgAECn8aAAIQAAYJ/CJ7CgA0AgAQAAYJ/CJ7CgA0AgAAAA==.Línk:BAAALgAECgYJCgAAAA==.',
['Lî']='Lîkwuid:BAAALgAECggJDwAAAA==.',
Ma='Macallan:BAAALgADCgMJBAAAAA==.Maddrox:BAAALgADCgcJDgAAAA==.Magicmarv:BAAALgADCgIJAQAAAA==.Magnagoth:BAAALgADCgkJDwAAAA==.Magnakilro:BAAALgAECgYJEwAAAA==.Mahnaz:BAAALgADCgEJAQABLgADCgcJCgAEAAAAAA==.Malanath:BAABLgAECn8XAAIFAAgJrBWpCwDNAQAFAAgJrBWpCwDNAQAAAA==.Malothas:BAAALgADCgQJBAAAAA==.Mareki:BAAALgADCgYJBwAAAA==.Markdfordeth:BAAALgADCgcJCAAAAA==.Mattyfu:BAAALgAECggJCgAAAA==.Mavíel:BAAALgAECgYJDQAAAA==.Maxrogue:BAAALgAECgIJAgABLgAECgQJEAAEAAAAAA==.Mazikeen:BAAALgAECgEJAQAAAA==.',
Mc='Mcscoots:BAAALgADCgcJDwAAAA==.',
Me='Meatsupreme:BAABLgAECn8lAAIOAAgJ4Qw3NgBrAQAOAAgJ4Qw3NgBrAQAAAA==.Meepin:BAACLgAFFH8KAAIgAAQJpRatEAD2AAAgAAQJpRatEAD2AAAuAAQKfyIAAiAACAkiJQMFABwDACAACAkiJQMFABwDAAAA.Meepmorp:BAAALgADCgIJAgAAAA==.Meifeng:BAAALgADCgEJAQAAAA==.Mephala:BAAALgADCgYJBgAAAA==.Mesophistole:BAAALgADCgMJAwABLgAECgMJAwAEAAAAAA==.Mesopyro:BAAALgAECgMJAwAAAA==.',
Mi='Mileenä:BAAALgADCgIJAgAAAA==.Minimim:BAAALgADCgMJAwAAAA==.Mià:BAAALgADCgEJAQAAAA==.',
Mo='Mod:BAAALgAECgcJEwAAAA==.Mograiné:BAAALgAECgIJAgAAAA==.Mojodaemon:BAAALgADCgMJAwAAAA==.Monkaw:BAAALgADCgUJBQAAAA==.Monkchalk:BAAALgAECgQJBAABLgAFFAMJCgASAH0kAA==.Moondevil:BAAALgADCgYJBwAAAA==.Morta:BAEALgAECgUJCwAAAA==.Mortkavaliro:BAAALgAECgQJBAAAAA==.',
Ms='Mslockness:BAAALgADCgUJBQAAAA==.',
Mu='Mugzy:BAAALgAECgkJBwAAAA==.Multipass:BAAALgAECgUJDAAAAA==.Multitool:BAAALgADCgEJAQAAAA==.',
['Mö']='Mörph:BAAALgAECgIJAgAAAA==.',
Na='Nadris:BAAALgADCgcJBwAAAA==.Nanérs:BAAALgAECgcJEQABLgAFFAMJBQAMAN8JAA==.Narrodus:BAAALgAECgYJEgAAAA==.Nasht:BAABLgAECn8UAAIdAAYJUBbgRgBaAQAdAAYJUBbgRgBaAQAAAA==.Nashxi:BAAALgADCgkJEAABLgAECgYJFAAdAFAWAA==.Nasu:BAAALgAECgcJAQAAAA==.Nattymoo:BAAALgAECgYJBwAAAA==.',
Ne='Necrô:BAAALgADCgIJAgAAAA==.',
Ni='Nightraven:BAAALgADCgkJCQAAAA==.Nightreaper:BAAALgADCgkJGwAAAA==.Nimbus:BAACLgAFFH8IAAICAAQJJgqDDQAhAQACAAQJJgqDDQAhAQAuAAQKfzEAAgIABwnHId4IABECAAIABwnHId4IABECAAEuAAUUBgkRAAUAoRcA.Nimike:BAAALgAECgcJDQAAAA==.',
No='Normul:BAAALgAECgcJAgABLgAECgkJKAANAIwgAA==.Noshoba:BAAALgAECgEJAQAAAA==.',
Nr='Nrvous:BAAALgADCgkJCQAAAA==.',
Nu='Nugzuul:BAAALgAECgEJAQAAAA==.Numbers:BAAALgAECgQJBwAAAA==.',
Ny='Nyterage:BAAALgAECgEJAQAAAA==.Nytesage:BAACLgAFFH8RAAIhAAQJgSQPAACsAQAhAAQJgSQPAACsAQAuAAQKfygAAiEACAkMJj8AAH4DACEACAkMJj8AAH4DAAAA.',
['Nä']='Näners:BAAALgAECgcJDQABLgAFFAMJBQAMAN8JAA==.',
Oo='Ookle:BAABLgAECn8gAAMPAAgJYAe+CQBLAQAPAAgJYAe+CQBLAQAIAAcJrgj0SACtAAAAAA==.',
Or='Oresh:BAABLgAECn8UAAITAAcJwA3zFwBxAQATAAcJwA3zFwBxAQAAAA==.Oryz:BAAALgADCgkJCAAAAA==.',
Os='Osajak:BAAALgADCgIJAgAAAA==.',
Oz='Ozo:BAAALgAECgcJBwAAAA==.',
Pa='Painavolian:BAABLgAECn8qAAIdAAgJcx7QFAA0AgAdAAgJcx7QFAA0AgAAAA==.Pandamonium:BAAALgAECgcJEgAAAA==.Panes:BAAALgAECgYJCgAAAA==.Paopu:BAAALgADCgYJBgABLgAECgkJIAAbAPcfAA==.',
Pe='Peeches:BAAALgAECgYJCgAAAA==.Pelor:BAAALgAECgMJAwAAAA==.',
Pi='Pisspadpanda:BAABLgAECn8oAAIbAAkJaiJEAwDxAgAbAAkJaiJEAwDxAgAAAA==.',
Po='Poggies:BAACLgAFFH8TAAIhAAYJ5iUFAAAsAgAhAAYJ5iUFAAAsAgAuAAQKfyEAAyEACAk0JjkAAIIDACEACAk0JjkAAIIDAB4AAQkOIPsWAGIAAAAA.Ponmonk:BAAALgAECgEJAQABLgAECgYJFQAUALcfAA==.Pontacos:BAABLgAECn8VAAIUAAYJtx++IADTAQAUAAYJtx++IADTAQAAAA==.Porkinator:BAAALgADCgYJCAAAAA==.Powdur:BAAALgADCgEJAQABLgAFFAMJBwAaAEQWAA==.Pozh:BAABLgAECn8UAAIbAAYJlA3+kAA3AQAbAAYJlA3+kAA3AQAAAA==.',
Pr='Praynes:BAABLgAECn8oAAIfAAkJtxfKEgBKAgAfAAkJtxfKEgBKAgAAAA==.Precedence:BAAALgADCgEJAQABLgAECgEJAQAEAAAAAA==.Prestocreamÿ:BAAALgADCgEJAQAAAA==.',
Pu='Pupperputh:BAAALgADCgkJEgABLgAECgkJIgADAKMdAA==.Puppet:BAAALgAECgEJAQAAAA==.',
Ra='Randyrando:BAAALgADCgIJBAAAAA==.Ranoe:BAAALgAECgcJEwAAAA==.Ravyniel:BAAALgADCgEJAQAAAA==.Razji:BAABLgAECn8rAAQaAAgJUiSDAQC+AgAaAAgJUyKDAQC+AgAKAAcJsSHHFwBsAgAJAAIJiSbSgQDjAAAAAA==.',
Re='Redrrum:BAAALgAECgcJCgAAAA==.Rekd:BAAALgADCgEJAQAAAA==.Reladiia:BAAALgADCgcJBwAAAA==.Revoked:BAAALgADCgEJAQABLgAECgYJDwAEAAAAAA==.Reznick:BAAALgAECgYJEQAAAA==.',
Ro='Rokd:BAAALgADCgcJBwAAAA==.Rokham:BAAALgADCgEJAQAAAA==.Rovërgalarga:BAAALgADCgMJAwAAAA==.',
Ru='Rudeboy:BAAALgAECgEJAQAAAA==.Ruibaron:BAAALgADCgkJIgAAAA==.',
Ry='Ryhunter:BAAALgADCggJDgAAAA==.',
['Rà']='Ràidèn:BAABLgAECn8bAAINAAgJIByzFQAMAgANAAgJIByzFQAMAgAAAA==.',
['Rá']='Ráyne:BAAALgAECgEJAQAAAA==.',
Sa='Sadeel:BAABLgAECn8nAAMiAAgJihqHAQD7AQAiAAcJaRyHAQD7AQAbAAgJKxKkRQD6AQAAAA==.Sadewolf:BAABLgAECn8lAAIDAAgJ/hzmBwBbAgADAAgJ/hzmBwBbAgAAAA==.Sadpanduh:BAAALgADCgkJFQAAAA==.Saltednuts:BAAALgAECgEJAQAAAA==.Samentoni:BAABLgAECn8lAAIgAAgJHBnPBgB0AgAgAAgJHBnPBgB0AgAAAA==.Samgal:BAAALgAECgYJDgAAAA==.Sardothien:BAAALgAECgEJAgAAAA==.Satyra:BAAALgAECgYJCwABLgAECggJHwAfALEiAA==.Saurphang:BAACLgAFFH8LAAMNAAUJ9Q8SGABFAQANAAQJ9Q8SGABFAQAjAAEJAACfJgAAAAAuAAQKfyoAAg0ACAn/IhEVAP0CAA0ACAn/IhEVAP0CAAAA.Saye:BAAALgADCgIJAgAAAA==.',
Sc='Scarletpanda:BAAALgADCgQJBgAAAA==.Scourgereap:BAAALgAECgMJAwAAAA==.',
Se='Selinna:BAAALgAECgYJDAAAAA==.Senpaichill:BAAALgAECgYJDQAAAA==.Severis:BAAALgADCgIJAgAAAA==.',
Sh='Shadiepope:BAAALgAECgEJAQAAAA==.Shadora:BAABLgAECn8bAAIUAAkJ8QqXCwDGAQAUAAkJ8QqXCwDGAQAAAA==.Shadowwizard:BAAALgAECgMJAwAAAA==.Shadybrat:BAAALgAECgYJDQABLgAFFAEJAQAEAAAAAA==.Shaggylol:BAAALgADCgcJDQAAAA==.Shamlazy:BAAALgADCgkJHQAAAA==.Shiroku:BAAALgAECgkJBgAAAA==.Shockchalk:BAACLgAFFH8KAAISAAMJfST2AgDQAAASAAMJfST2AgDQAAAuAAQKfycAAxIACAluJuUCAA8DABIACAluJuUCAA8DAAIAAglPEYY6AIEAAAAA.Shocknorris:BAAALgAECgQJBwABLgAECgYJDwAEAAAAAA==.Shrooclaw:BAABLgAECn8UAAIIAAgJGBLEQQCaAQAIAAgJGBLEQQCaAQAAAA==.',
Si='Sibbiah:BAAALgAECgMJAgAAAA==.Silanre:BAAALgAECgYJEQAAAA==.',
Sk='Skaðï:BAABLgAECn8pAAQKAAkJ+SHGAADIAgAKAAgJ5yLGAADIAgAaAAIJ2hHlIQCPAAAJAAMJLxitZwCOAAAAAA==.',
Sm='Smolshrapnel:BAAALgAECgUJCQAAAA==.',
Sn='Sneakchalk:BAAALgADCgcJCwABLgAFFAMJCgASAH0kAA==.',
So='Solaraze:BAABLgAECn8YAAIOAAgJ8Rt5PAAyAgAOAAgJ8Rt5PAAyAgAAAA==.Solinarie:BAAALgADCgIJAgAAAA==.Sorrowfang:BAAALgAECgEJAQAAAA==.Sovnightwar:BAAALgAECgMJAwAAAA==.Soza:BAAALgADCgEJAQAAAA==.',
Sp='Spacespecial:BAAALgAECgYJCwAAAA==.Sparklebunny:BAAALgADCgEJAQAAAA==.Spicycurryy:BAABLgAECn8iAAQJAAgJTiDrDQAsAgAJAAgJTiDrDQAsAgAaAAIJwgTjJgBgAAAKAAIJJAy3eABeAAABLgAECggJIgAJAE4gAA==.Spiker:BAAALgAECgEJAQAAAA==.Splittail:BAAALgAECgQJBAAAAA==.',
St='Strahm:BAAALgAECgQJEAAAAA==.Strehm:BAAALgADCgEJAgABLgAECgQJEAAEAAAAAA==.Strohmy:BAAALgADCgEJAQABLgAECgQJEAAEAAAAAA==.Stryhm:BAAALgADCgMJBAABLgAECgQJEAAEAAAAAA==.',
Su='Sunju:BAAALgADCgMJAwAAAA==.',
Sy='Syssare:BAABLgAECn8XAAIRAAcJZSK0BAAvAgARAAcJZSK0BAAvAgAAAA==.',
Ta='Tabbie:BAAALgADCgYJBgAAAA==.Talasam:BAAALgADCgcJCAAAAA==.Talien:BAAALgADCgEJAQAAAA==.Tandsonnara:BAAALgAECgkJDAAAAA==.Tastetickle:BAABLgAECn8pAAIdAAkJYR7ZBQDcAgAdAAkJYR7ZBQDcAgAAAA==.Tazdrin:BAABLgAECn8pAAIkAAkJZhQ3AQAvAgAkAAkJZhQ3AQAvAgAAAA==.',
Te='Telidrus:BAACLgAFFH8OAAIdAAUJARvzFABtAQAdAAUJARvzFABtAQAuAAQKfycABB0ACAkqIGYxAK0CAB0ABwkmI2YxAK0CAB4ABAmjHe0CAHEBACEAAglVE5wHAEoAAAAA.Temok:BAAALgADCgEJAQAAAA==.Teyrlis:BAAALgAECgQJBQAAAA==.',
Th='Thavryn:BAAALgADCgYJBgAAAA==.Thias:BAAALgAECgcJEQAAAA==.Thukwarlock:BAABLgAECn8dAAIbAAcJ7xgmSQDuAQAbAAcJ7xgmSQDuAQAAAA==.Thunderbug:BAAALgADCgEJAQAAAA==.',
To='Todd:BAAALgAECgEJAQAAAA==.Tokain:BAAALgADCgkJEQAAAA==.Topaze:BAAALgAECgUJCAAAAA==.Torironheart:BAAALgADCgcJBwAAAA==.',
Tr='Trance:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.Treehuggera:BAAALgAECgYJCgAAAA==.Tribunal:BAAALgAECgEJAQAAAA==.Trilila:BAAALgADCgYJBgAAAA==.Tripx:BAAALgAECgYJDwABLgAECgYJGgADAK8aAA==.Tronko:BAABLgAECn8ZAAIBAAgJBRr5DgADAgABAAgJBRr5DgADAgAAAA==.Trumpinator:BAAALgADCgUJAQAAAA==.',
Ts='Tsireya:BAAALgADCgcJCQABLgAECgQJDgAEAAAAAA==.',
Tu='Turntsnaco:BAABLgAECn8fAAIWAAgJpxstBgAXAgAWAAgJpxstBgAXAgAAAA==.Tusk:BAAALgAECgcJEQAAAA==.',
Tw='Twigger:BAAALgADCgEJAQAAAA==.Twiztedsoul:BAAALgADCgcJBwAAAA==.Twophorb:BAAALgADCgMJAwAAAA==.',
Ua='Uake:BAAALgADCgYJBgAAAA==.',
Ud='Udgar:BAAALgAECggJDAAAAA==.',
Un='Unafhaen:BAAALgADCgEJAQAAAA==.Unaverse:BAAALgAECgEJAQAAAA==.',
Us='Usmccpl:BAAALgAECgMJAwAAAA==.Usmcsemperfi:BAAALgADCgYJCQAAAA==.',
Va='Valengarde:BAABLgAECn8ZAAIOAAgJpBRYIwC4AQAOAAgJpBRYIwC4AQAAAA==.Vanette:BAAALgAECgEJAQAAAA==.Vannix:BAABLgAECn8oAAIUAAkJ1CGpAAAvAwAUAAkJ1CGpAAAvAwAAAA==.Vanz:BAAALgADCgIJAgAAAA==.Varnos:BAAALgAECgEJAQAAAA==.',
Ve='Velranis:BAAALgADCgMJAwAAAA==.Velthas:BAAALgADCggJHwAAAA==.',
Vi='Virmethir:BAAALgAECgUJDgAAAA==.Viruz:BAAALgADCgcJCgAAAA==.',
Vy='Vylaran:BAAALgADCgYJBgAAAA==.Vyndrolan:BAAALgAECgMJCAAAAA==.Vyroth:BAAALgADCgUJBQAAAA==.',
Wa='Walksonwater:BAAALgADCgEJAQABLgAECgYJEgAEAAAAAA==.Waq:BAAALgAECgYJCQAAAA==.',
We='Wellamor:BAAALgADCgEJAQAAAA==.',
Wi='Wiwi:BAABLgAECn8oAAMNAAkJjCCjAwD3AgANAAkJjCCjAwD3AgAlAAIJCRt2CgCmAAAAAA==.',
Xa='Xares:BAABLgAECn8fAAIdAAgJ7BhRIADrAQAdAAgJ7BhRIADrAQAAAA==.',
Xe='Xerath:BAAALgADCgcJBwAAAA==.',
Xh='Xhades:BAAALgAECgQJBAAAAA==.',
Ya='Yalda:BAAALgAECgUJBwAAAA==.',
Yf='Yfra:BAAALgAECgYJDQAAAA==.',
Yo='Yobama:BAAALgAECgUJCQABLgAECggJIgANAFohAA==.Yochangsvegn:BAAALgAECgcJDwAAAA==.Yoseph:BAAALgAECgcJEAAAAA==.',
Yu='Yurimancer:BAABLgAECn8ZAAIUAAYJhRLdGQAvAQAUAAYJhRLdGQAvAQAAAA==.',
Za='Zaen:BAAALgADCgMJAwAAAA==.Zake:BAAALgAECgMJBAAAAA==.Zalileina:BAAALgADCgMJAwAAAA==.Zallith:BAAALgADCgMJAwABLgAECgYJDgAEAAAAAA==.Zappythile:BAABLgAECn8cAAIBAAgJABlfEgDdAQABAAgJABlfEgDdAQAAAA==.Zarkamental:BAAALgADCgYJCwAAAA==.',
Ze='Zect:BAAALgAECgUJEQAAAA==.Zelinor:BAAALgADCgcJBwAAAA==.',
Zi='Ziêg:BAAALgADCgcJBwAAAA==.',
Zo='Zoz:BAAALgAECgMJAwAAAA==.',
Zu='Zulfrik:BAABLgAECn8dAAIdAAgJVBaHKADDAQAdAAgJVBaHKADDAQAAAA==.Zullard:BAAALgAECgEJAQAAAA==.',
Zy='Zyzy:BAAALgAECgMJAwABLgAECgYJDgAEAAAAAA==.',
['Zõ']='Zõke:BAAALgADCgEJAQAAAA==.',
['Òd']='Òdb:BAAALgADCgEJAQAAAA==.',
['ße']='ßeef:BAAALgADCgcJBwAAAA==.',
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
