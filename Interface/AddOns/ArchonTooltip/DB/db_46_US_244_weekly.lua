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

local lookup = {'Unknown-Unknown','Druid-Restoration','Paladin-Protection','Paladin-Retribution','Hunter-BeastMastery','DemonHunter-Vengeance','Warlock-Demonology','Monk-Mistweaver','Monk-Windwalker','Hunter-Marksmanship','Mage-Frost','Mage-Arcane','DeathKnight-Unholy','Druid-Balance','Warlock-Destruction','Hunter-Survival','Monk-Brewmaster','Priest-Shadow','Shaman-Elemental','DeathKnight-Blood','DemonHunter-Havoc','Warlock-Affliction','DemonHunter-Devourer','Priest-Holy','Warrior-Protection','Shaman-Enhancement','Warrior-Fury','Shaman-Restoration','Rogue-Assassination','Paladin-Holy','Druid-Guardian','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Warrior-Arms',}
local provider = {region='US',realm='Zangarmarsh',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aaminae:BAAALgAECgYJEwAAAA==.',
Ab='Abora:BAAALgADCgUJBwABLgAECgEJAQABAAAAAA==.Abracadaver:BAAALgADCgcJEQAAAA==.Abracastabya:BAAALgAECggJDgAAAA==.Abraxys:BAAALgADCgIJAgAAAA==.',
Ad='Adachï:BAAALgAECgYJCQABLgAECggJFgACANMbAA==.Adune:BAAALgADCgEJAQABLgAECgYJEAABAAAAAA==.',
Ae='Aedar:BAAALgAECgUJCwAAAA==.Aethlin:BAABLgAECn8XAAMDAAYJCxoCBAB/AQADAAYJCxoCBAB/AQAEAAYJtQ/1nQBDAQAAAA==.Aeturnas:BAAALgAECgYJEgAAAA==.',
Ag='Agralesia:BAAALgADCgcJBwAAAA==.',
Al='Aldky:BAAALgADCgkJDgAAAA==.Aliana:BAAALgAECgIJAgAAAA==.Allindis:BAAALgAECgYJCQABLgAECggJEAABAAAAAA==.Allypally:BAAALgADCgMJAwAAAA==.Alphamage:BAAALgADCgMJAwAAAA==.Alphamonk:BAAALgAECgQJBwAAAA==.Alros:BAABLgAECn8VAAIFAAcJrRUBDQChAQAFAAcJrRUBDQChAQAAAA==.Alslock:BAAALgADCgIJAgAAAA==.Alvaah:BAAALgADCgUJBQAAAA==.',
Am='Amardyton:BAAALgADCgkJCQAAAA==.',
Ar='Archon:BAAALgADCgQJBAABLgAECgIJAgABAAAAAA==.Arctica:BAAALgADCgQJBAAAAA==.Arette:BAAALgAECgIJAgAAAA==.Arkades:BAAALgAECgYJDQAAAA==.Arkshade:BAAALgAECgQJDwAAAA==.Armorup:BAAALgAECgUJCAAAAA==.Artaz:BAAALgAECgQJAwABLgAECggJHgAGAOIhAA==.Aryn:BAAALgADCgQJBAAAAA==.',
As='Asmo:BAAALgADCgUJEAAAAA==.Astarii:BAAALgAECgEJAQAAAA==.Asterica:BAABLgAECn8eAAIHAAgJihggCgDRAQAHAAgJihggCgDRAQAAAA==.',
At='Atormentor:BAAALgADCgIJAQAAAA==.',
Au='Auggystyle:BAAALgAECgYJCwAAAA==.Auriaza:BAAALgAECgYJEgAAAA==.',
Av='Averynicole:BAAALgAECgUJCQAAAA==.',
Aw='Awasjr:BAAALgAECgYJEAAAAA==.',
Ay='Ayano:BAAALgAECgYJBwAAAA==.',
['Añ']='Añimorph:BAAALgAECgEJAQAAAA==.',
Ba='Balazar:BAAALgADCggJDwAAAA==.Balthïer:BAAALgAECgUJCAABLgAECggJFgACANMbAA==.Bark:BAAALgAECgYJBgAAAA==.',
Be='Beanfist:BAAALgADCgkJDgAAAA==.Bearhug:BAABLgAECn8jAAMIAAgJExVtIACxAQAIAAcJ1hZtIACxAQAJAAYJhAh2QgANAQAAAA==.Beasty:BAABLgAECn8XAAIKAAYJ9w6tRABCAQAKAAYJ9w6tRABCAQAAAA==.Beatriixx:BAAALgADCgMJAwAAAA==.Bee:BAABLgAECn8aAAIDAAgJ7yJjAgARAwADAAgJ7yJjAgARAwAAAA==.Beeb:BAAALgAECgUJDAABLgAECggJGgADAO8iAA==.Beefisting:BAAALgAECgQJBwABLgAECggJGgADAO8iAA==.Belardor:BAAALgAECgcJBwAAAA==.Beliara:BAAALgAECgQJBwAAAA==.Bellamere:BAAALgADCgkJCAAAAA==.Beverage:BAAALgAECgEJAQAAAA==.',
Bi='Bionarra:BAAALgAECgYJEwAAAA==.Bishopwr:BAAALgAECgYJCwAAAA==.Bittertøfu:BAAALgAECgYJEAAAAA==.',
Bl='Blackwidöw:BAAALgAECgIJAgAAAA==.Blitê:BAAALgADCgUJBQABLgADCgkJDQABAAAAAA==.',
Bm='Bmpfrostie:BAAALgAECgcJCwAAAA==.',
Bo='Bocay:BAAALgADCgEJAQABLgAECggJEQABAAAAAA==.Bohica:BAAALgAECgQJBwAAAA==.Booker:BAAALgADCgUJBQAAAA==.Boonn:BAAALgAECggJEAAAAA==.Boorne:BAAALgADCgQJBAAAAA==.',
Br='Brakug:BAABLgAECn8hAAMLAAgJrSPECQANAgALAAgJrSPECQANAgAMAAEJBw7RHgAzAAAAAA==.Braywyat:BAAALgADCgUJBQAAAA==.Breck:BAAALgADCgYJBgABLgADCgcJBwABAAAAAA==.Brekk:BAAALgAECgIJAgAAAA==.Brem:BAABLgAECn8VAAIMAAcJsBsfBAASAgAMAAcJsBsfBAASAgAAAA==.Bretagnesse:BAAALgAECgYJDAAAAA==.Briara:BAAALgADCgkJCQAAAA==.Brittyy:BAAALgADCgUJBgAAAA==.Broníx:BAAALgAECgEJAQAAAA==.Bropeep:BAABLgAECn8VAAINAAYJbCLeOABTAgANAAYJbCLeOABTAgAAAA==.',
Bu='Bullshott:BAAALgAECgYJEgAAAA==.Bum:BAABLgAECn8iAAMOAAkJrh/5BABRAwAOAAkJrh/5BABRAwACAAEJ0xCE0QAtAAAAAA==.Bumagak:BAAALgADCgMJAwAAAA==.',
By='Bylun:BAAALgAECgkJAwAAAA==.',
['Bè']='Bèrtim:BAAALgADCgEJAQAAAA==.',
Ca='Caeruleum:BAAALgAECgQJBQAAAA==.Calyen:BAAALgADCgkJFQABLgAECgQJCgABAAAAAA==.Canmm:BAAALgAECgIJAgAAAA==.Carartha:BAABLgAECn8WAAIEAAgJLAW8KAAAAQAEAAgJLAW8KAAAAQAAAA==.Carrots:BAAALgAECgUJDQAAAA==.Cashmachine:BAABLgAECn8aAAIFAAcJHRgTDACsAQAFAAcJHRgTDACsAQAAAA==.Catfight:BAAALgAECgQJCgAAAA==.',
Ch='Chagall:BAAALgADCgcJEAAAAA==.Charcoal:BAABLgAECn8jAAMHAAgJwxdiLgBTAgAHAAgJwxdiLgBTAgAPAAEJAABYZwBBAAAAAA==.Charlié:BAAALgADCggJCAAAAA==.Chasebakes:BAABLgAECn8XAAQKAAgJPyCBGABlAgAKAAgJpB+BGABlAgAFAAMJShl0IAD+AAAQAAMJDhgBDgCXAAAAAA==.Cheesecake:BAAALgAECgYJEQAAAA==.Choks:BAAALgAECgQJCQAAAA==.Chubbycat:BAAALgAECgcJDQAAAA==.Chuggz:BAABLgAECn8VAAIRAAYJCRUSCgBOAQARAAYJCRUSCgBOAQAAAA==.Chéfboyrlee:BAACLgAFFH8KAAISAAUJGBReAwC2AQASAAUJGBReAwC2AQAuAAQKfyUAAhIACQnpGxQHABkDABIACQnpGxQHABkDAAAA.',
Ci='Cizmac:BAAALgADCgkJGgAAAA==.',
Cn='Cnari:BAAALgADCgEJAQAAAA==.',
Co='Corruptdata:BAAALgADCgYJBgAAAA==.Cownado:BAAALgAECgQJCgAAAA==.',
Cr='Crouton:BAAALgADCgkJCgAAAA==.',
Cy='Cybelem:BAABLgAECn8ZAAITAAgJ7B0sAwATAgATAAgJ7B0sAwATAgAAAA==.Cynleel:BAAALgAECgQJBwABLgAECgYJCQABAAAAAA==.Cyris:BAAALgAECgEJAQAAAA==.',
Da='Damonstyle:BAAALgAECgEJAQAAAA==.Dandistyle:BAAALgAECggJEgAAAA==.Darkshe:BAAALgAECgEJAgAAAA==.Darrot:BAAALgADCgUJBQAAAA==.Daz:BAAALgADCgUJBQAAAA==.',
De='Deadgeinside:BAAALgADCgIJAgAAAA==.Deathnom:BAAALgADCgEJAQAAAA==.Deeviant:BAAALgAECgQJBwAAAA==.Delrager:BAAALgAFFAEJAQAAAA==.',
Di='Dibbydab:BAAALgAECgYJDQAAAA==.',
Dj='Django:BAABLgAECn8cAAMOAAgJLCKpEACaAgAOAAcJvSGpEACaAgACAAIJjgY/MgBGAAAAAA==.Djatalon:BAAALgAECgMJBgAAAA==.Djderpyderpy:BAAALgAECgQJBAAAAA==.Djehrtey:BAAALgADCgYJCgAAAA==.Djin:BAAALgAECgEJAQABLgAECgYJEQABAAAAAA==.Djinni:BAAALgAECgYJEQAAAA==.',
Do='Doodle:BAAALgAECgYJEwAAAA==.Dorlen:BAAALgADCgYJCgAAAA==.',
Dr='Dracnahr:BAAALgAECgYJDgAAAA==.Dracpriest:BAAALgADCgQJBAAAAA==.Draffut:BAAALgADCgkJGQAAAA==.Dramaticus:BAAALgADCgEJAQAAAA==.Drfear:BAAALgAECgMJAwAAAA==.Drifabell:BAAALgADCgcJEgAAAA==.',
Du='Dumblegear:BAAALgAECgYJDAAAAA==.',
Dy='Dychi:BAAALgAECgYJBwAAAA==.Dyvoke:BAAALgADCgEJAQABLgAECgYJBwABAAAAAA==.',
Dz='Dzi:BAAALgADCgIJAgAAAA==.',
['Dä']='Däbeëfmäster:BAAALgADCgQJBgAAAA==.',
Ed='Edinna:BAAALgAECgYJDwAAAA==.',
Ek='Ekatrina:BAAALgADCgkJDgAAAA==.',
El='Elara:BAAALgADCgQJBAAAAA==.Elessedil:BAAALgAECgQJBwAAAA==.Ellariia:BAAALgADCgYJBgAAAA==.Ellemystic:BAAALgADCgcJEQAAAA==.Elyriana:BAABLgAECn8ZAAICAAgJbyKfAQDJAgACAAgJbyKfAQDJAgAAAA==.',
Em='Emberzz:BAAALgAECgUJBgAAAA==.Emeralda:BAAALgAECgEJAQAAAA==.Emila:BAEALgADCgkJFgABLgAECgYJBgABAAAAAA==.Emokilla:BAAALgADCgkJGwAAAA==.Empusia:BAAALgADCgMJAwAAAA==.Emriq:BAAALgAECgQJBwAAAA==.',
En='Encounter:BAAALgADCgMJAwAAAA==.Enrique:BAABLgAECn8jAAIEAAgJYRwjIQCmAgAEAAgJYRwjIQCmAgAAAA==.',
Er='Erazath:BAAALgAECgEJAQABLgAECgcJGAAUAC4VAA==.Erufuyokai:BAAALgADCgUJBQAAAA==.Erusdh:BAAALgADCgIJAgAAAA==.',
Es='Esha:BAAALgADCgkJDgAAAA==.',
Ev='Evolv:BAAALgAECgkJCAAAAA==.Evöö:BAAALgADCgUJAwAAAA==.',
Ey='Eysis:BAAALgADCgUJBQAAAA==.',
Fa='Faerdya:BAAALgAECgYJDgAAAA==.Falar:BAAALgAECgQJBgAAAA==.Favel:BAABLgAECn8eAAIGAAgJ4iFOAQAcAwAGAAgJ4iFOAQAcAwAAAA==.',
Fc='Fckvwls:BAAALgADCgYJCgAAAA==.',
Fe='Fearlesfreep:BAABLgAECn8YAAIFAAYJ5xHFTACDAQAFAAYJ5xHFTACDAQAAAA==.Febz:BAABLgAECn8eAAILAAgJbBslMACyAgALAAgJbBslMACyAgAAAA==.Febzy:BAAALgAECgQJBQAAAA==.Felatonin:BAAALgAECgcJDQAAAA==.Felfüry:BAABLgAECn8WAAMVAAYJxAyCCQAEAQAVAAYJxAyCCQAEAQAGAAIJNwIYKgA7AAAAAA==.Fenixshaw:BAAALgADCgkJHQAAAA==.Feudal:BAAALgAECggJEAAAAA==.Feyd:BAAALgAECgYJDQAAAA==.',
Fi='Fin:BAAALgADCgcJEAAAAA==.Finella:BAAALgAECgMJBAAAAA==.Finneas:BAAALgADCgUJBQABLgAECgYJDQABAAAAAA==.Firefire:BAAALgAECgMJAwAAAA==.Fistsofurry:BAAALgAECgQJBAABLgAECgMJBAABAAAAAA==.',
Fj='Fjeighty:BAAALgAECgQJCAAAAA==.',
Fo='Foggpy:BAABLgAECn8ZAAQWAAcJAyB1BAA2AgAWAAYJRyR1BAA2AgAHAAYJmxa9VwDAAQAPAAUJ3hoOHwBYAQAAAA==.',
Fr='Frederich:BAAALgADCgcJBwAAAA==.Freyke:BAAALgADCgUJBQAAAA==.Frostybear:BAABLgAECn8eAAILAAgJZhBsEwCmAQALAAgJZhBsEwCmAQAAAA==.Frostydk:BAAALgAECgcJBwAAAA==.Fröstmöurne:BAAALgAECgYJDwAAAA==.',
['Fé']='Félindra:BAAALgADCgQJAgAAAA==.',
Ga='Galaythien:BAAALgADCgkJEwAAAA==.Garai:BAAALgADCgYJBgAAAA==.Garrex:BAAALgADCgcJFAABLgAFFAIJCAAXAC0cAA==.',
Ge='Geret:BAAALgAECgYJEgAAAA==.Gezabelle:BAAALgADCgIJAgAAAA==.',
Gi='Gigihadid:BAAALgADCgYJBgAAAA==.',
Gl='Glitchy:BAABLgAECn8bAAIOAAgJOxmlBADSAQAOAAgJOxmlBADSAQAAAA==.Glokraz:BAAALgAECgcJAQAAAA==.Glowbark:BAAALgADCgcJBwAAAA==.Glumpto:BAAALgAECgMJAwAAAA==.',
Gn='Gnomage:BAAALgADCgUJBQAAAA==.',
Go='Goingtogetu:BAABLgAECn8bAAIDAAgJEiGJAQATAgADAAgJEiGJAQATAgAAAA==.Goldfarmr:BAABLgAECn8ZAAIYAAgJBhydDwBqAgAYAAgJBhydDwBqAgAAAA==.Goldshocker:BAAALgAECgQJBAAAAA==.Golduwu:BAAALgAECgEJAQAAAA==.Gorlami:BAAALgAECgcJBgAAAA==.',
Gr='Greeley:BAAALgAECgcJEAAAAA==.Gregdapro:BAABLgAECn8aAAIUAAgJsiAbBQDxAgAUAAgJsiAbBQDxAgAAAA==.Gregnstone:BAAALgAECgYJDwABLgAECggJGgAUALIgAA==.Grimmnstrous:BAAALgADCgEJAQAAAA==.',
Gu='Gunnhunter:BAAALgAECgYJDQABLgAFFAQJCQABAAAAAQ==.Gunnyal:BAAALgAECgQJCQAAAA==.',
Gw='Gwencthlan:BAAALgAECgEJAQAAAA==.',
Gy='Gyathew:BAABLgAECn8ZAAITAAgJsCHqAQBUAgATAAgJsCHqAQBUAgAAAA==.',
Ha='Haerin:BAAALgADCgEJAgABLgADCgYJCQABAAAAAA==.Hagunn:BAAALgAFFAQJCQAAAQ==.Hakyahi:BAAALgADCggJCAAAAA==.Hank:BAAALgADCgYJBgAAAA==.Harkin:BAABLgAECn8VAAIEAAYJ+hKXigBmAQAEAAYJ+hKXigBmAQAAAA==.Harnzak:BAAALgADCgEJAQABLgAECgQJBAABAAAAAA==.Hatchett:BAAALgADCgkJFAAAAA==.',
He='Heatfrezze:BAAALgAECgYJBgAAAA==.Heresurstick:BAAALgAECgYJEwAAAA==.Hevy:BAABLgAECn8WAAIXAAYJJxGTdABHAQAXAAYJJxGTdABHAQABLgAECgcJBwABAAAAAA==.',
Hi='Hilarius:BAAALgAECggJCwAAAA==.Hiraeth:BAAALgAECgMJAwAAAA==.',
Ho='Holydadbod:BAAALgAECgEJAQABLgAECgYJEQABAAAAAA==.Holyman:BAAALgADCgMJAwAAAA==.Holyshots:BAABLgAECn8YAAIEAAgJbw9+FQB0AQAEAAgJbw9+FQB0AQAAAA==.Howlinnbrews:BAAALgAECgQJBAAAAA==.Howlinplague:BAAALgAECgQJBAAAAA==.',
Hu='Hulkhogan:BAAALgAECgYJEAAAAA==.Hunttal:BAAALgAECgEJAQAAAA==.',
Ia='Iamnoone:BAACLgAFFH8IAAIXAAIJLRw+IwC0AAAXAAIJLRw+IwC0AAAuAAQKfyIAAhcACAnuIaoVANQCABcACAnuIaoVANQCAAAA.',
Id='Idcaboutyou:BAAALgADCgkJBgAAAA==.Idrion:BAAALgAECggJDgAAAA==.',
Ig='Ignore:BAAALgADCgYJBgAAAA==.Igotdabrewz:BAAALgAECgYJEwAAAA==.',
Il='Illorin:BAAALgADCgcJDgAAAA==.Illuvatari:BAAALgAECgEJAQAAAA==.',
In='Incindia:BAAALgADCgEJAQAAAA==.',
Io='Iobo:BAAALgAECgQJCQAAAA==.',
Ir='Ironhidez:BAAALgAECgYJEAAAAA==.',
Is='Ishiza:BAAALgADCggJDQAAAA==.',
Ja='Jabiso:BAAALgAECgUJCQAAAA==.Jacinto:BAAALgAFFAEJAQABLgAFFAQJCgANAD4WAA==.Jastia:BAAALgAECgMJCAAAAA==.Jayce:BAAALgADCgcJBwAAAA==.',
Je='Jekelez:BAAALgADCgYJCQAAAA==.Jetblack:BAABLgAECn8XAAMHAAcJfhcuEACQAQAHAAcJfhcuEACQAQAPAAEJAADlbQA5AAAAAA==.Jezter:BAAALgAECgcJBgAAAA==.',
Jh='Jharlin:BAAALgAECgUJDAAAAA==.',
Jo='Joecephus:BAAALgAECgQJBAAAAA==.Joehex:BAABLgAECn8VAAIZAAYJ7B+nDQAwAgAZAAYJ7B+nDQAwAgAAAA==.Joulez:BAAALgADCgMJAQAAAA==.',
Ju='Judgematt:BAAALgAECgUJBQAAAA==.Justin:BAAALgAECgQJCQAAAA==.',
Ka='Kaevianda:BAAALgAECgUJCAAAAA==.Kageshootman:BAABLgAECn8VAAIKAAYJLw5YBgATAQAKAAYJLw5YBgATAQAAAA==.Kaleesh:BAABLgAECn8ZAAIaAAgJLyRIAQBoAwAaAAgJLyRIAQBoAwAAAA==.Kallux:BAAALgAECgYJEgAAAA==.Kananga:BAAALgAECgQJCgAAAA==.Karavira:BAAALgADCgcJDwAAAA==.Kasca:BAAALgADCgYJBgAAAA==.Kaybar:BAAALgADCgIJAgAAAA==.',
Ke='Kelindina:BAAALgAECgMJCQAAAA==.Kelindinas:BAAALgAECgQJBwAAAA==.Kevinshart:BAAALgAECgUJBQAAAA==.',
Kh='Khalli:BAAALgADCgcJEQAAAA==.',
Ki='Kieleron:BAAALgAECgMJAwAAAA==.Kierlessa:BAAALgAECgYJCQABLgAECggJJAATADIcAA==.Kiermac:BAAALgAECgUJDgAAAA==.Kiermaxim:BAABLgAECn8kAAITAAgJMhwYGwA6AgATAAgJMhwYGwA6AgAAAA==.Kiragrande:BAAALgAECggJEQAAAA==.Kiraneth:BAABLgAECn8XAAIJAAYJIA4aDAAPAQAJAAYJIA4aDAAPAQAAAA==.Kirial:BAAALgADCgcJBwAAAA==.Kiriku:BAAALgAECgYJBgAAAA==.',
Kl='Klaysdnds:BAAALgADCggJEgAAAA==.',
Ko='Kobus:BAAALgADCgQJBAAAAA==.Korbinf:BAAALgAECgQJCAAAAA==.Kotok:BAAALgAECgQJBAAAAA==.',
Ku='Kungpownibs:BAAALgADCgUJBQAAAA==.',
La='Larplord:BAAALgAECgYJDQAAAA==.',
Ld='Ldyelphaba:BAAALgAECgUJCAAAAA==.',
Li='Lilchungus:BAAALgADCgIJAwAAAA==.Liturgy:BAAALgADCgMJAwAAAA==.',
Lo='Logankord:BAABLgAECn8VAAIbAAYJKSRFBgDBAQAbAAYJKSRFBgDBAQAAAA==.Lokeira:BAABLgAECn8eAAIcAAcJGho9KQDqAQAcAAcJGho9KQDqAQAAAA==.Lolded:BAAALgADCgEJAQAAAA==.Lono:BAAALgAECgYJEgAAAA==.Loop:BAAALgADCgMJAwAAAA==.Lorcana:BAAALgAECgEJAQAAAA==.Lorstus:BAAALgADCgYJBgAAAA==.',
Lu='Lucory:BAAALgADCgcJBQABLgAECgQJCwABAAAAAA==.Lumberjack:BAAALgADCgQJBgAAAA==.Luvbug:BAABLgAECn8UAAIFAAYJeySBGAB2AgAFAAYJeySBGAB2AgAAAA==.',
Ly='Lyara:BAACLgAFFH8IAAMcAAMJYCUOBAAzAQAcAAMJYCUOBAAzAQATAAIJ/QcxGQCPAAAuAAQKfxgAAxwACAkVIE8JAOICABwACAkVIE8JAOICABMABAnmEvpaANgAAAAA.Lythos:BAABLgAECn8YAAIUAAcJLhVoGwBzAQAUAAcJLhVoGwBzAQAAAA==.Lyu:BAAALgAECgYJCQABLgAFFAMJCAAcAGAlAA==.Lyuu:BAAALgAFFAEJAgABLgAFFAMJCAAcAGAlAA==.',
['Lø']='Lørdøfßud:BAABLgAECn8UAAIbAAYJFB8cCACfAQAbAAYJFB8cCACfAQAAAA==.',
Ma='Macguffin:BAAALgADCgkJDgAAAA==.Machomans:BAAALgAECgEJAQABLgAECgYJDAABAAAAAA==.Malifae:BAABLgAECn8WAAIOAAcJYSGXEwB3AgAOAAcJYSGXEwB3AgAAAA==.Malimae:BAAALgADCgYJBgABLgAECgcJFgAOAGEhAA==.Mankilla:BAAALgADCgUJBQAAAA==.Mansa:BAABLgAECn8UAAIdAAYJvRf0CQCZAQAdAAYJvRf0CQCZAQAAAA==.Mastamojo:BAAALgAECgYJEQAAAA==.Maulding:BAAALgADCgcJDgAAAA==.',
Mc='Mcmurphy:BAAALgAECgUJCQAAAA==.Mctanky:BAAALgAECgEJAQAAAA==.',
Me='Mechadragon:BAAALgADCgYJDwAAAA==.Meepmeep:BAAALgAECgQJBQAAAA==.Meissen:BAAALgAECgYJEQAAAA==.Melendaren:BAAALgADCgkJFAAAAA==.Melestaria:BAAALgAECgEJAQAAAA==.Meltara:BAAALgADCgUJBQAAAA==.Menonk:BAAALgADCgQJBQAAAA==.Meowandi:BAAALgAECgIJAgAAAA==.Merscy:BAAALgAECgYJEgAAAA==.Mertia:BAAALgAECgQJCgAAAA==.Messìah:BAAALgAECgYJCQAAAA==.Metamonster:BAAALgAECgYJCwAAAA==.Meåny:BAAALgAECgYJCQAAAA==.',
Mi='Mikimiku:BAAALgADCgUJBQAAAA==.Miniav:BAAALgADCgkJGgAAAA==.Mirko:BAAALgAECgYJDAAAAA==.Mistyjoe:BAAALgADCgMJAwAAAA==.',
Ml='Mladjo:BAAALgAECgYJDAAAAA==.',
Mo='Mockery:BAABLgAECn8ZAAIMAAcJ3BP6BwB8AQAMAAcJ3BP6BwB8AQAAAA==.Mokokniki:BAAALgADCggJCAAAAA==.Moneie:BAAALgADCgYJBgAAAA==.Monger:BAAALgADCgIJAgAAAA==.Monkyourself:BAAALgADCgYJCQAAAA==.Mooana:BAAALgADCgMJAwAAAA==.Moocowman:BAAALgAECgYJDgABLgAECgcJBwABAAAAAA==.Moone:BAAALgADCgYJBgAAAA==.Morticiá:BAAALgAECgYJCQAAAA==.Mortiferum:BAAALgADCgcJDQAAAA==.Mourningstar:BAAALgAFFAQJBAABLgAFFAQJCgANAD4WAA==.Mozaic:BAABLgAECn8ZAAIZAAcJMRWlBQBVAQAZAAcJMRWlBQBVAQAAAA==.',
Mu='Mugrüíth:BAAALgADCggJFQAAAA==.',
My='Myragê:BAAALgADCgkJDQAAAA==.Myselia:BAAALgAECgMJAwAAAA==.Mystra:BAAALgADCgEJAQAAAA==.',
Na='Naek:BAAALgADCgkJFwAAAA==.Natawista:BAAALgADCgcJEgAAAA==.',
Ne='Necromus:BAAALgAECgQJCgAAAA==.Nekra:BAAALgADCgEJAQAAAA==.',
Ni='Nibbi:BAAALgADCgEJAQAAAA==.Nic:BAAALgADCgEJAQAAAA==.Nichtaire:BAAALgAECgYJEAAAAA==.Niem:BAAALgAECgcJEwAAAA==.Nilyaf:BAAALgADCgQJBAAAAA==.',
No='Nocturnum:BAAALgAECgYJEwAAAA==.Notkorbin:BAAALgAECgEJAQAAAA==.Notreeus:BAAALgAECgEJAQAAAA==.Nowotrius:BAAALgADCgUJBQAAAA==.',
Nu='Numb:BAAALgAECgYJDAAAAA==.',
Ny='Nyxstryl:BAACLgAFFH8HAAIWAAQJRQ9PAABcAQAWAAQJRQ9PAABcAQAuAAQKfxsAAhYACAktHi8BAPECABYACAktHi8BAPECAAAA.',
['Nô']='Nôkiaa:BAAALgAECgQJBgAAAA==.',
Ob='Obitus:BAAALgADCgEJAQABLgAECgYJCQABAAAAAA==.',
Od='Odahviing:BAAALgADCgQJBAAAAA==.Odin:BAAALgADCgYJBgAAAA==.',
Oh='Ohuln:BAAALgADCgcJCAABLgAFFAUJEAAKAMQZAA==.',
Ol='Oldmage:BAAALgADCgUJBQAAAA==.Oldmongerpal:BAAALgADCgYJBgAAAA==.',
On='Onetwocowpow:BAABLgAECn8bAAIIAAgJaxcIBAD9AQAIAAgJaxcIBAD9AQAAAA==.',
Oo='Ooshiny:BAAALgAECgEJAQAAAA==.',
Or='Orclard:BAAALgAECgIJAgAAAA==.Ordanith:BAABLgAECn8eAAIEAAgJryC9AwBsAgAEAAgJryC9AwBsAgAAAA==.Orionn:BAACLgAFFH8HAAIFAAMJDB6uCQAUAQAFAAMJDB6uCQAUAQAuAAQKfygAAgUACAkhJG4GACYDAAUACAkhJG4GACYDAAAA.Ornan:BAAALgAECgQJBAAAAA==.Ororo:BAAALgAECgIJAgAAAA==.',
Os='Osø:BAAALgAECgYJCwAAAA==.',
Ov='Oven:BAABLgAECn8YAAIJAAYJbBp6BwBiAQAJAAYJbBp6BwBiAQAAAA==.',
Pa='Pastaa:BAAALgAECgcJEwAAAA==.',
Ph='Phil:BAAALgAECgcJEwAAAA==.Phillio:BAAALgAECgQJBAAAAA==.Phoenixy:BAAALgADCgQJBAAAAA==.Phosphate:BAAALgAECgYJCQAAAA==.',
Pi='Pippins:BAAALgAECgEJAQAAAA==.',
Pl='Plunto:BAAALgADCgUJBQAAAA==.',
Po='Po:BAAALgAECgYJCQAAAA==.Portucala:BAAALgADCgYJCQAAAA==.',
Pr='Prarg:BAAALgADCgcJBwAAAA==.Praystation:BAAALgAECgUJCAAAAA==.',
Py='Pyral:BAAALgAECgYJDAAAAA==.',
Ra='Raekeshh:BAAALgAECggJDwAAAA==.Raelone:BAAALgAECgYJDQAAAA==.Rageofmommy:BAAALgADCgMJAwAAAA==.Raidoe:BAABLgAECn8aAAMIAAgJrhkXEABaAgAIAAgJrhkXEABaAgAJAAEJ9QzGfgAxAAAAAA==.Raknaruk:BAAALgAECgEJAQAAAA==.Rakwiz:BAAALgADCgEJAQAAAA==.Rangérz:BAAALgAECgYJEwAAAA==.Rant:BAAALgAECgQJBgAAAA==.Rasa:BAAALgAECgUJCAAAAA==.Ratio:BAAALgADCgYJBgAAAA==.',
Re='Redshammy:BAAALgAECgQJBAAAAA==.Redward:BAAALgAECgYJEAAAAA==.',
Rh='Rhielle:BAABLgAECn8kAAIeAAgJOyDCDQCqAgAeAAgJOyDCDQCqAgAAAA==.',
Ri='Rinche:BAABLgAECn8aAAMcAAgJaQn6EgAdAQAcAAgJaQn6EgAdAQATAAQJkxDmWwDTAAAAAA==.Rintche:BAAALgAECgEJAQAAAA==.',
Ro='Rolland:BAAALgAECgQJBgAAAA==.Rollf:BAAALgADCgUJBQAAAA==.Rootbeamxo:BAAALgADCgUJBgAAAA==.Rosefyre:BAAALgAECgMJAwAAAA==.',
Ru='Rudo:BAABLgAECn8WAAIFAAgJaBRbIgA3AgAFAAgJaBRbIgA3AgAAAA==.Rumproblem:BAAALgAECgYJCgAAAA==.Runnamuuk:BAABLgAECn8ZAAIXAAYJXAo7KADZAAAXAAYJXAo7KADZAAAAAA==.Rush:BAAALgAECgEJAQAAAA==.',
Ry='Ryeger:BAAALgAECgYJEgAAAA==.',
['Rä']='Räsa:BAAALgAECgEJAQAAAA==.',
['Ró']='Róótbear:BAABLgAECn8ZAAIfAAYJOBMXFAAvAQAfAAYJNxMXFAAvAQAAAA==.',
Sa='Sadrobot:BAAALgAECgEJAQABLgAECgMJCQABAAAAAA==.Salfros:BAAALgADCgkJCwAAAA==.Sallydapally:BAAALgADCgYJBwAAAA==.Samovar:BAABLgAECn8UAAIEAAcJAAmMIwAbAQAEAAcJAAmMIwAbAQAAAA==.Sandbones:BAAALgADCgEJAQABLgAECgcJGQAMANwTAA==.Sandraice:BAABLgAECn8YAAIEAAgJxgYwhwBsAQAEAAgJxgYwhwBsAQAAAA==.Sandwiches:BAAALgAECgYJEgAAAA==.Sanguinne:BAAALgAECgIJAgAAAA==.Sansami:BAABLgAECn8XAAIRAAYJHBymJQDWAQARAAYJHBymJQDWAQAAAA==.Sarraloesh:BAAALgADCgIJAgAAAA==.',
Sc='Scalebagz:BAAALgAECgcJEAAAAA==.Schism:BAAALgADCgkJDgAAAA==.',
Se='Selûne:BAAALgAECgMJBQAAAA==.Sentren:BAAALgADCgcJDAAAAA==.Senyorseven:BAAALgAECgQJCAAAAA==.Seo:BAAALgADCgUJBQAAAA==.Setresh:BAABLgAECn8eAAIQAAgJVxODAgD1AQAQAAgJVxODAgD1AQAAAA==.',
Sh='Shadöwsöng:BAAALgAECgUJEAAAAA==.Shaedelana:BAAALgAECgMJBgAAAA==.Shamrox:BAAALgADCgkJDwAAAA==.Shamwowhex:BAAALgAECgYJBgAAAA==.Shangöh:BAAALgADCgMJAwABLgAECggJFgACANMbAA==.Shinygoat:BAAALgADCgIJAgABLgAECggJHgAGAOIhAA==.Shivyn:BAABLgAECn8WAAMcAAcJJQZVVwAqAQAcAAcJJQZVVwAqAQATAAEJFwWojQAqAAAAAA==.Shokyo:BAAALgADCgUJBQAAAA==.Shoota:BAAALgAECgEJAQABLgAFFAUJEAAKAMQZAA==.Shugarion:BAAALgADCgUJAQAAAA==.Shàken:BAAALgADCgYJCgAAAA==.',
Si='Sibadeekay:BAABLgAECn8iAAMNAAgJHhekDwCaAQANAAgJHhekDwCaAQAUAAUJrQ9VLgDMAAAAAA==.Sickkid:BAABLgAECn8VAAIbAAUJiRP3EgAKAQAbAAUJiRP3EgAKAQAAAA==.Siegekaiser:BAAALgADCgcJEwAAAA==.Silvershine:BAAALgAECgYJDwAAAA==.Sindrya:BAAALgAECgMJBQAAAA==.',
Sk='Skoobastank:BAAALgADCgIJAgAAAA==.Skunkt:BAAALgADCgYJCAAAAA==.',
Sl='Slimeto:BAAALgAECgIJAgAAAA==.',
Sm='Smaeg:BAAALgAECgMJAwABLgAECgcJDAABAAAAAA==.Smeef:BAAALgAECgQJBAAAAA==.Smoothvelvet:BAAALgAECgYJDAAAAA==.',
Sn='Snays:BAAALgAECgYJEAAAAA==.Sneeger:BAAALgAECgIJAgAAAA==.Snuggles:BAAALgAECgQJCgABLgAECggJGgAQABwZAA==.',
So='Solidgen:BAAALgAECgEJAQAAAA==.Solobolo:BAAALgAECgQJBAABLgAECgQJBAABAAAAAA==.Sosreaper:BAAALgADCgYJCgAAAA==.',
Sp='Spadez:BAAALgAECgYJDQAAAA==.Splortus:BAAALgAECgEJAQAAAA==.Sprath:BAAALgAECgEJAQAAAA==.Sprinkle:BAAALgAECgMJBgAAAA==.',
Ss='Ssraeshza:BAAALgAECgYJDAABLgAFFAQJCgADAKMVAA==.',
St='Staretra:BAABLgAECn8bAAMSAAgJ7hIqMABhAQASAAYJ3A8qMABhAQAYAAMJlQNPFwB2AAAAAA==.Stficyhot:BAAALgADCgMJBgAAAA==.',
Su='Sungjinwoo:BAAALgAECgYJBwAAAA==.Sunslap:BAAALgAECgYJEAAAAA==.Susanaa:BAAALgAECgUJBwAAAA==.',
Sy='Symana:BAABLgAECn8XAAIYAAcJnhxYFAA7AgAYAAcJnhxYFAA7AgAAAA==.Syradra:BAAALgAECgEJAQAAAA==.Sytka:BAAALgADCgcJCgAAAA==.',
['Sè']='Sèan:BAAALgADCgcJDAAAAA==.',
['Sì']='Sìlvertìger:BAAALgAECgYJBgAAAA==.',
Ta='Taadra:BAABLgAECn8ZAAIcAAcJDRwcBAA1AgAcAAcJDRwcBAA1AgAAAA==.Talfuki:BAAALgADCgUJBQAAAA==.Taliliia:BAAALgAECgEJAQAAAA==.Talkova:BAAALgAECgYJDgAAAA==.Talohae:BAAALgAECggJEgAAAA==.Talona:BAAALgAECgQJBAABLgAFFAQJBwAWAEUPAA==.Tandaan:BAAALgADCgkJCQABLgAECggJDwABAAAAAA==.Tanjent:BAAALgAECgMJBgAAAA==.Tapio:BAAALgAECgQJCgAAAA==.Tatsumå:BAAALgAECgUJCAABLgAECgYJCwABAAAAAA==.',
Te='Terp:BAAALgAECgMJBgAAAA==.',
Th='Thalrissa:BAAALgAECgMJAwAAAA==.Thort:BAAALgAECgMJAwAAAA==.Thuglifé:BAAALgADCgYJDQAAAA==.',
Ti='Tia:BAAALgAECgEJAQAAAA==.Tidemaiden:BAAALgAECgYJEAAAAA==.Tiktac:BAAALgADCgMJAwAAAA==.Tinynflaccid:BAAALgADCgMJAwAAAA==.Tipsymancer:BAABLgAECn8bAAIRAAgJGho7AwAIAgARAAgJGho7AwAIAgAAAA==.Tirael:BAAALgAECgYJBQAAAA==.',
To='Touji:BAAALgADCgcJDAAAAA==.',
Tr='Treesus:BAABLgAECn8YAAIOAAgJxxWPGwAmAgAOAAgJxxWPGwAmAgAAAA==.Trinket:BAAALgADCgEJAQABLgAECggJFgAFAGgUAA==.Trollroom:BAAALgADCgkJCQAAAA==.',
Tw='Twinklehoofs:BAAALgAECgIJAgAAAA==.Twiztid:BAAALgADCgYJCAAAAA==.',
Ty='Tyrethal:BAAALgADCgcJBwAAAA==.',
['Tñ']='Tñer:BAAALgAECggJEgAAAA==.',
Ul='Ulahwekeheia:BAAALgAECggJEAAAAA==.',
Us='Usidore:BAAALgADCgcJBwAAAA==.',
Va='Vainin:BAAALgAECgIJAgAAAA==.Valle:BAAALgAECgQJBAAAAA==.Variable:BAAALgADCgEJAQAAAA==.Vashdin:BAAALgAECgQJCgAAAA==.',
Ve='Vectorvega:BAAALgAECgEJAQABLgAECggJFgAFAGgUAA==.Veicilia:BAAALgAECgMJAwAAAA==.Velashis:BAAALgAECgcJDgAAAA==.Velshariel:BAAALgADCgUJBQAAAA==.Vermin:BAAALgAECgcJBwAAAA==.',
Vi='Viable:BAAALgAECgQJBgAAAA==.Vibes:BAAALgADCgkJEQAAAA==.Victorvega:BAAALgAECgEJAQABLgAECggJFgAFAGgUAA==.Vilt:BAAALgADCgMJAwAAAA==.Visandar:BAAALgAECgcJDQAAAA==.Vivif:BAAALgAFFAMJBAAAAA==.Vixsin:BAAALgADCgQJCgAAAA==.',
Vo='Vordilina:BAAALgAECggJDgAAAA==.',
Vr='Vresim:BAABLgAECn8WAAQgAAcJhRjvEwAGAgAgAAcJhRjvEwAGAgAhAAQJyhjKNQBnAAAiAAEJyAO6IgAtAAAAAA==.',
Vu='Vuginhood:BAAALgADCgEJAgAAAA==.Vugnus:BAAALgAECgQJCgAAAA==.',
Vy='Vynarras:BAAALgAECgUJBwAAAA==.',
['Vé']='Véxx:BAAALgAECgYJEQAAAA==.',
Wa='Wannan:BAAALgADCgYJCQAAAA==.Wardamon:BAAALgADCgYJBgABLgAECgEJAgABAAAAAA==.Warihor:BAABLgAECn8YAAMbAAcJEwk5EQAeAQAbAAcJ6wg5EQAeAQAjAAYJxAS7IgDXAAAAAA==.',
We='Weezle:BAAALgAECgMJBgAAAA==.Westrin:BAABLgAECn8cAAIWAAgJdB9FAwBsAgAWAAgJdB9FAwBsAgAAAA==.',
Wi='Wife:BAAALgAECgIJAgAAAA==.Wiz:BAAALgADCgcJDAAAAA==.',
Wo='Worgendork:BAAALgAECgcJBgAAAA==.',
Wr='Wrangler:BAAALgAECgcJBAAAAA==.',
Wy='Wyndeline:BAAALgAECgMJBgAAAA==.',
Xa='Xarrie:BAAALgADCgMJCQAAAA==.',
Xc='Xc:BAAALgADCgcJBwAAAA==.',
Xo='Xorxel:BAAALgADCgcJFwAAAA==.',
Ya='Yacob:BAAALgAECggJEQAAAA==.',
Yg='Yggrasdil:BAABLgAECn8WAAICAAgJ0xvkAwBYAgACAAgJ0xvkAwBYAgAAAA==.',
Yh='Yhwach:BAAALgAFFAIJAgAAAA==.',
Yi='Yikes:BAAALgADCgEJAQAAAA==.',
Ym='Ymir:BAAALgAECgcJDQABLgAECgMJBAABAAAAAA==.',
Yo='Yolasses:BAAALgAECgUJCgAAAA==.',
Yu='Yuie:BAAALgAECgEJAQAAAA==.Yukitaiga:BAAALgAECgQJCAAAAA==.Yule:BAAALgAECgQJBAAAAA==.',
Za='Zaeden:BAAALgAECgYJEgAAAA==.Zaftdh:BAABLgAECn8XAAIXAAgJZxDrDgCRAQAXAAgJZxDrDgCRAQAAAA==.Zaha:BAABLgAECn8eAAILAAYJ2CKrXAAkAgALAAYJ2CKrXAAkAgAAAA==.Zaidane:BAAALgADCgYJBgAAAA==.Zarov:BAAALgADCgQJBAAAAA==.Zarthan:BAAALgAECgEJAQAAAA==.',
Zd='Zdps:BAAALgAECgQJAgAAAA==.',
Ze='Zem:BAAALgAECgYJEgAAAA==.Zeroultra:BAAALgAECgYJEwAAAA==.Zeusmos:BAABLgAECn8ZAAIJAAcJUCN3AQBeAgAJAAcJUCN3AQBeAgAAAA==.',
Zi='Zithenex:BAAALgAECgQJCgAAAA==.',
Zw='Zwar:BAAALgADCggJEAAAAA==.',
Zy='Zynsis:BAAALgADCgYJCQAAAA==.',
['Ál']='Álister:BAAALgADCgkJFQAAAA==.',
['Ér']='Éragon:BAAALgAECgYJEwAAAA==.',
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
