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

local lookup = {'Rogue-Subtlety','Unknown-Unknown','Druid-Restoration','Paladin-Protection','Paladin-Retribution','Paladin-Holy','Hunter-BeastMastery','DeathKnight-Unholy','DemonHunter-Vengeance','Warlock-Demonology','Shaman-Restoration','Monk-Mistweaver','Monk-Windwalker','Hunter-Marksmanship','Mage-Frost','Shaman-Elemental','Mage-Arcane','Druid-Balance','Monk-Brewmaster','Warlock-Destruction','Hunter-Survival','Priest-Shadow','DeathKnight-Frost','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Blood','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Affliction','Priest-Holy','Warrior-Fury','Warrior-Arms','Druid-Feral','Warrior-Protection','Shaman-Enhancement','Rogue-Assassination','Druid-Guardian','Mage-Fire',}
local provider = {region='US',realm='Zangarmarsh',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aaminae:BAABLgAECn8UAAIBAAcJkw8nLgCRAQABAAcJkw8nLgCRAQAAAA==.',
Ab='Abora:BAAALgADCgUJBwABLgAECgEJAQACAAAAAA==.Abracadaver:BAAALgAECgQJBAAAAA==.Abracastabya:BAAALgAECggJDwAAAA==.Abraxys:BAAALgADCgIJAgAAAA==.',
Ad='Adachï:BAAALgAECgYJEwABLgAECggJHgADADkfAA==.Adevil:BAAALgADCgEJAQAAAA==.Adune:BAAALgADCgEJAQABLgAECgYJEAACAAAAAA==.',
Ae='Aedar:BAAALgAECgYJDQAAAA==.Aethlin:BAABLgAECn8YAAMEAAcJuhlKBgDEAQAEAAcJuhlKBgDEAQAFAAYJtQ/3nQBDAQAAAA==.Aeturnas:BAABLgAECn8ZAAIGAAcJwhsvCQBEAgAGAAcJwhsvCQBEAgAAAA==.',
Ag='Agralesia:BAAALgADCgkJCQAAAA==.',
Al='Aldky:BAAALgADCgkJDgAAAA==.Aliana:BAAALgAECgIJAgAAAA==.Allindis:BAAALgAECgYJCQABLgAECggJGAADAMgYAA==.Allypally:BAAALgADCgMJAwAAAA==.Alphamage:BAAALgADCgMJAwAAAA==.Alphamonk:BAAALgAECgYJCQAAAA==.Alros:BAABLgAECn8dAAIHAAgJ7BljDQAyAgAHAAgJ7BljDQAyAgAAAA==.Alslock:BAAALgADCgIJAgAAAA==.Alvaah:BAAALgADCgUJBQAAAA==.',
Am='Amardyton:BAAALgAECgUJBQAAAA==.',
Ar='Archon:BAAALgADCgQJBAABLgAECgIJAgACAAAAAA==.Arctica:BAAALgADCgQJBAAAAA==.Arette:BAAALgAECgIJAgAAAA==.Arkades:BAAALgAECgYJDQAAAA==.Arkshade:BAABLgAECn8UAAIIAAUJfw9pXwDoAAAIAAUJfw9pXwDoAAAAAA==.Armorup:BAAALgAECgUJCAAAAA==.Artaz:BAAALgAECgQJAwABLgAECggJKAAJAAEiAA==.Aryn:BAAALgADCgQJBAAAAA==.',
As='Ashez:BAAALgADCgMJAgABLgAECgIJAgACAAAAAA==.Asmo:BAAALgADCggJFwAAAA==.Astarii:BAAALgAECgEJAgAAAA==.Asterica:BAABLgAECn8nAAIKAAkJNBYjFAAEAgAKAAkJNBYjFAAEAgAAAA==.',
At='Atormentor:BAAALgADCgIJAQAAAA==.',
Au='Auggystyle:BAAALgAECgYJCwAAAA==.Auriaza:BAABLgAECn8YAAILAAYJ+A17UwA4AQALAAYJ+A17UwA4AQAAAA==.',
Av='Averynicole:BAAALgAECgUJDQAAAA==.',
Aw='Awasjr:BAABLgAECn8YAAIHAAgJGxuqDgAkAgAHAAgJGxuqDgAkAgAAAA==.',
Ay='Ayano:BAAALgAECgYJCQAAAA==.',
['Añ']='Añimorph:BAAALgAECgQJBQAAAA==.',
Ba='Balazar:BAAALgAECgQJCAAAAA==.Balthïer:BAAALgAECgUJDQABLgAECggJHgADADkfAA==.Bark:BAAALgAECgYJBgAAAA==.',
Be='Beanfist:BAAALgADCgkJDgAAAA==.Bearhug:BAABLgAECn8jAAMMAAgJExVeIACwAQAMAAcJ1hZeIACwAQANAAYJhAh5QgANAQABLgAFFAIJAwACAAAAAA==.Bearshock:BAAALgAFFAIJAwAAAA==.Beasty:BAABLgAECn8XAAIOAAYJ9w6pRABCAQAOAAYJ9w6pRABCAQAAAA==.Beatriixx:BAAALgAECgEJAQAAAA==.Bee:BAABLgAECn8gAAIEAAgJ+iRkAgARAwAEAAgJ+iRkAgARAwAAAA==.Beeb:BAAALgAECgUJDQABLgAECggJIAAEAPokAA==.Beefisting:BAAALgAECgQJBwABLgAECggJIAAEAPokAA==.Belardor:BAAALgAECgkJBwAAAA==.Beliara:BAAALgAECgUJCAAAAA==.Bellamere:BAAALgADCgkJCAAAAA==.Beverage:BAAALgAECgEJAQAAAA==.',
Bi='Bionarra:BAABLgAECn8aAAIPAAcJpxd+MwCXAQAPAAcJpxd+MwCXAQAAAA==.Bishopwr:BAAALgAECgYJCwAAAA==.Bittertøfu:BAABLgAECn8WAAIQAAYJlQbcKwDSAAAQAAYJlQbcKwDSAAAAAA==.',
Bl='Blackwidöw:BAAALgAECgIJAwAAAA==.Blaire:BAAALgADCgcJAQAAAA==.Blitê:BAAALgADCgUJBQABLgADCgkJDQACAAAAAA==.',
Bm='Bmpfrostie:BAAALgAECgcJDwAAAA==.',
Bo='Bocay:BAAALgADCgEJAQABLgAECggJEQACAAAAAA==.Bohica:BAAALgAECgYJCQAAAA==.Booker:BAAALgADCgUJBQAAAA==.Boonn:BAAALgAECggJEQAAAA==.Boorne:BAAALgADCgQJBAAAAA==.',
Br='Brakug:BAABLgAECn8nAAMPAAgJ6SOKGwAGAgAPAAgJ6SOKGwAGAgARAAEJBw7QHgAzAAAAAA==.Braywyat:BAAALgADCgUJBQAAAA==.Breck:BAAALgAECgIJAgAAAA==.Brekk:BAAALgAECgIJBAAAAA==.Brem:BAABLgAECn8WAAIRAAgJYxkeBAASAgARAAgJYxkeBAASAgAAAA==.Bretagnesse:BAABLgAECn8UAAISAAgJ3AWlGwAeAQASAAgJ3AWlGwAeAQAAAA==.Briara:BAAALgADCgkJCQAAAA==.Brittyy:BAAALgADCgUJBgAAAA==.Broníx:BAAALgAECgEJAwAAAA==.Bropeep:BAABLgAECn8bAAIIAAYJASP5IADCAQAIAAYJASP5IADCAQAAAA==.',
Bu='Bullshott:BAAALgAECgcJEwAAAA==.Bum:BAABLgAECn8mAAMSAAkJrh/4BABRAwASAAkJrh/4BABRAwADAAEJ0xCF0QAtAAAAAA==.Bumagak:BAAALgADCgMJAwAAAA==.Butts:BAAALgAECgIJAgAAAA==.',
By='Bylun:BAAALgAECgkJCAAAAA==.',
['Bè']='Bèrtim:BAAALgADCgEJAQAAAA==.',
Ca='Caeruleum:BAAALgAECgQJBQAAAA==.Calyen:BAAALgADCgkJFQABLgAECgYJFQATAGsIAA==.Canmm:BAAALgAECgIJAgAAAA==.Carartha:BAABLgAECn8eAAIFAAgJVAbCRgA1AQAFAAgJVAbCRgA1AQAAAA==.Carrots:BAAALgAECgUJDQAAAA==.Cashmachine:BAABLgAECn8aAAIHAAcJHRiuIACdAQAHAAcJHRiuIACdAQAAAA==.Catfight:BAAALgAECgUJDwAAAA==.',
Ch='Chagall:BAAALgADCgcJEAAAAA==.Charcoal:BAABLgAECn8pAAMKAAgJShhLGwDRAQAKAAgJShhLGwDRAQAUAAEJAABfZwBBAAAAAA==.Charlié:BAAALgADCggJCAAAAA==.Chasebakes:BAABLgAECn8XAAQOAAgJPyCEGABlAgAOAAgJpB+EGABlAgAHAAMJShkJSAD5AAAVAAMJDhhRIQCUAAAAAA==.Cheesecake:BAABLgAECn8WAAIUAAYJOg1EJgAtAQAUAAYJOg1EJgAtAQAAAA==.Choks:BAAALgAECgUJDgAAAA==.Chromie:BAAALgADCgMJAwAAAA==.Chubbycat:BAAALgAECgcJDQAAAA==.Chuggz:BAABLgAECn8dAAITAAgJoxgDCAATAgATAAgJoxgDCAATAgAAAA==.Chéfboyrlee:BAACLgAFFH8OAAIWAAUJJRZkAwC1AQAWAAUJJRZkAwC1AQAuAAQKfyYAAhYACQnpGxgHABkDABYACQnpGxgHABkDAAAA.',
Ci='Cizmac:BAAALgADCgkJIQAAAA==.',
Cl='Clinictrials:BAAALgAECgYJBgAAAA==.',
Cn='Cnari:BAAALgADCgEJAQAAAA==.',
Co='Corruptdata:BAAALgADCgYJBwAAAA==.Cownado:BAABLgAECn8VAAITAAYJawiUIwDpAAATAAYJawiUIwDpAAAAAA==.',
Cr='Crouton:BAAALgADCgkJCgAAAA==.',
Cy='Cybelem:BAABLgAECn8hAAIQAAgJCx5kCAAaAgAQAAgJCx5kCAAaAgAAAA==.Cyfelen:BAAALgADCgcJBwAAAA==.Cynleel:BAAALgAECgYJCQAAAA==.Cyris:BAAALgAECgMJAwAAAA==.',
Da='Damonstyle:BAAALgAECgEJAQAAAA==.Dandistyle:BAABLgAECn8bAAMTAAkJdh15AgC4AgATAAkJax15AgC4AgANAAEJchKnfAAzAAAAAA==.Darkshe:BAAALgAECgEJAgAAAA==.Darrot:BAAALgADCgUJBQAAAA==.Daz:BAAALgADCgUJBQAAAA==.',
De='Deadgeinside:BAAALgADCgIJAgAAAA==.Deathnom:BAAALgADCgEJAQAAAA==.Deeviant:BAAALgAECgYJCQAAAA==.Defend:BAAALgAECgYJBgABLgAFFAMJCAATAAsKAA==.Delrager:BAAALgAFFAEJAQAAAA==.',
Di='Dibbydab:BAAALgAECgYJEwAAAA==.',
Dj='Django:BAABLgAECn8kAAMSAAgJOSFEAwCeAgASAAgJOSFEAwCeAgADAAIJjgaKbQBFAAAAAA==.Djatalon:BAAALgAECgQJCgAAAA==.Djderpyderpy:BAAALgAECgUJBwAAAA==.Djehrtey:BAAALgADCgYJCgAAAA==.Djin:BAAALgAECgEJAQABLgAECgYJFwANAOEbAA==.Djinni:BAABLgAECn8XAAMNAAYJ4RvjEABxAQATAAYJ4RtyKADDAQANAAYJABnjEABxAQAAAA==.',
Do='Doffy:BAAALgAECgEJAQAAAA==.Doodle:BAABLgAECn8WAAMXAAYJfBjABQDVAQAXAAYJfBjABQDVAQAIAAMJsA1w/QCAAAAAAA==.Dorlen:BAAALgADCgYJCgAAAA==.',
Dr='Dracnahr:BAABLgAECn8VAAQYAAcJ0BcXBgDsAQAYAAcJ0BcXBgDsAQAZAAQJmQzGJgDVAAAaAAEJAAB6PAA8AAAAAA==.Dracpriest:BAAALgADCgQJBAAAAA==.Draffut:BAAALgADCgkJGQAAAA==.Dramaticus:BAAALgADCgEJAQAAAA==.Drfear:BAAALgAECgMJAwAAAA==.Drifabell:BAAALgADCgcJEgAAAA==.',
Du='Dumblegear:BAAALgAECgYJDAAAAA==.',
Dy='Dychi:BAAALgAECgYJBwAAAA==.Dyvoke:BAAALgADCgEJAQABLgAECgYJBwACAAAAAA==.',
Dz='Dzi:BAAALgADCgIJAgAAAA==.',
['Dä']='Däbeëfmäster:BAAALgADCgQJBgAAAA==.',
Ed='Edinna:BAAALgAECggJEQAAAA==.',
Ek='Ekatrina:BAAALgADCgkJDgAAAA==.',
El='Elara:BAAALgADCgQJBAAAAA==.Elessedil:BAAALgAECgYJCQAAAA==.Ellariia:BAAALgADCgYJBgAAAA==.Ellemystic:BAAALgADCgcJGAAAAA==.Elyriana:BAABLgAECn8bAAIDAAgJbyLWBQC+AgADAAgJbyLWBQC+AgAAAA==.',
Em='Emberzz:BAAALgAECgUJCAAAAA==.Emeralda:BAAALgAECgEJAQAAAA==.Emila:BAEALgAECgYJCgAAAA==.Emokilla:BAAALgADCgkJGwAAAA==.Empusia:BAAALgADCgMJAwAAAA==.Emriq:BAAALgAECgYJCQAAAA==.',
En='Encounter:BAAALgADCgMJAwAAAA==.Enrique:BAABLgAECn8rAAIFAAgJpx0DFQATAgAFAAgJpx0DFQATAgAAAA==.',
Er='Erazath:BAAALgAECgEJAQABLgAECggJGQAbAIwTAA==.Erufuyokai:BAAALgADCgUJBQAAAA==.Erusdh:BAAALgADCgIJAgAAAA==.',
Es='Esha:BAAALgADCgkJDgAAAA==.Estanna:BAAALgAECgcJAgAAAA==.',
Ev='Evolv:BAAALgAECgkJCAAAAA==.Evöö:BAAALgADCgUJAwAAAA==.',
Ey='Eysis:BAAALgADCgUJBQAAAA==.',
Fa='Faerdya:BAAALgAECgYJDgAAAA==.Falar:BAAALgAECgYJCAAAAA==.Favel:BAABLgAECn8oAAMJAAgJASJOAQAcAwAJAAgJ4iFOAQAcAwAcAAgJ7wrkJwBIAQAAAA==.',
Fc='Fckvwls:BAAALgADCgYJCgAAAA==.',
Fe='Fearlesfreep:BAABLgAECn8gAAIHAAgJhRA0IwCQAQAHAAgJhRA0IwCQAQAAAA==.Febz:BAABLgAECn8eAAIPAAgJbBsoMACyAgAPAAgJbBsoMACyAgAAAA==.Febzy:BAAALgAECgQJBQAAAA==.Felatonin:BAAALgAECgcJDQAAAA==.Felfüry:BAABLgAECn8WAAMdAAYJxAzbFQD1AAAdAAYJxAzbFQD1AAAJAAIJNwIaKgA7AAAAAA==.Fenixshaw:BAAALgADCgkJHQAAAA==.Feudal:BAAALgAECggJEAAAAA==.Feyd:BAAALgAECgYJDQAAAA==.',
Fi='Fin:BAAALgADCgcJEAAAAA==.Finella:BAAALgAECgMJBAAAAA==.Finneas:BAAALgADCgUJBQABLgAECgYJDQACAAAAAA==.Firefire:BAAALgAECgMJAwAAAA==.Fistsofurry:BAAALgAECgQJBAABLgAECgMJBAACAAAAAA==.',
Fj='Fjeighty:BAAALgAECgUJDQAAAA==.',
Fo='Foggpy:BAABLgAECn8gAAQeAAgJ/R91BAA2AgAeAAYJRyR1BAA2AgAKAAYJCBu9VwDAAQAUAAYJXxkRHwBYAQAAAA==.',
Fr='Frederich:BAAALgAECgMJAwAAAA==.Freyke:BAAALgADCgUJBQAAAA==.Frostlicious:BAAALgADCgEJAQAAAA==.Frostybear:BAABLgAECn8nAAIPAAkJ2BH8GQAQAgAPAAkJ2BH8GQAQAgAAAA==.Frostydk:BAAALgAECgcJBwAAAA==.Fröstmöurne:BAABLgAECn8bAAIbAAYJsge0GgClAAAbAAYJsge0GgClAAAAAA==.',
['Fé']='Félindra:BAAALgADCgQJAgAAAA==.',
Ga='Galaythien:BAAALgADCgkJGgAAAA==.Garai:BAAALgADCgYJBgAAAA==.Garrex:BAAALgADCgcJFAABLgAFFAMJCgAcAJ0XAA==.',
Ge='Geret:BAABLgAECn8aAAIFAAcJMRI8MwB1AQAFAAcJMRI8MwB1AQAAAA==.Gezabelle:BAAALgADCgIJAgAAAA==.',
Gi='Gigihadid:BAAALgADCgYJBgAAAA==.',
Gl='Glitchy:BAABLgAECn8jAAISAAgJQxtACQD8AQASAAgJQxtACQD8AQAAAA==.Glokraz:BAAALgAECgcJAQAAAA==.Glowbark:BAAALgADCgcJBwAAAA==.Glumpto:BAAALgAECgQJBwAAAA==.',
Gn='Gnomage:BAAALgADCgUJBQAAAA==.',
Go='Goingtogetu:BAABLgAECn8jAAIEAAgJpCHHAQCNAgAEAAgJpCHHAQCNAgAAAA==.Gold:BAAALgAECgIJAgAAAA==.Goldfarmr:BAABLgAECn8dAAIfAAgJ7RwrBgBYAgAfAAgJ7RwrBgBYAgAAAA==.Goldshocker:BAAALgAECgQJBAAAAA==.Golduwu:BAAALgAECgEJAQAAAA==.Gorlami:BAAALgAECgcJBgAAAA==.',
Gr='Greeley:BAABLgAECn8YAAIOAAgJ2xurAgAbAgAOAAgJ2xurAgAbAgAAAA==.Gregdapro:BAABLgAECn8iAAIbAAgJXyEdBQDxAgAbAAgJXyEdBQDxAgAAAA==.Gregnstone:BAABLgAECn8XAAIGAAgJrxgnEQDXAQAGAAgJrxgnEQDXAQABLgAECggJIgAbAF8hAA==.Grimmnstrous:BAAALgADCgEJAQABLgAFFAIJAgACAAAAAA==.',
Gu='Gunnhunter:BAAALgAECgYJDQABLgAFFAUJEAAgAM8cAA==.Gunnyal:BAAALgAECgUJDgAAAA==.',
Gw='Gwencthlan:BAAALgAECgEJAQAAAA==.',
Gy='Gyathew:BAABLgAECn8fAAIQAAgJDCPsAgCvAgAQAAgJDCPsAgCvAgAAAA==.',
Ha='Haerin:BAAALgADCgEJAgABLgADCgYJCQACAAAAAA==.Hagunn:BAACLgAFFH8QAAMgAAUJzxxXAwB/AQAgAAUJzxxXAwB/AQAhAAEJNAEIDgA8AAAuAAQKfzAAAyAACQlGIrkDAJICACAACQk8IrkDAJICACEAAwlRHE4QAAgBAAAA.Hakyahi:BAAALgADCggJCAAAAA==.Hank:BAAALgADCgYJBgAAAA==.Harkin:BAABLgAECn8dAAIFAAgJWQ/NLwCDAQAFAAgJWQ/NLwCDAQAAAA==.Harnzak:BAAALgADCgEJAQABLgAECgQJBAACAAAAAA==.Hatchett:BAAALgADCgkJGwAAAA==.',
He='Heatfrezze:BAAALgAECgYJBgAAAA==.Heresurstick:BAABLgAECn8aAAIQAAcJUQsGHQAuAQAQAAcJUQsGHQAuAQAAAA==.Hevy:BAABLgAECn8fAAIcAAgJlBRtGAClAQAcAAgJlBRtGAClAQAAAA==.',
Hi='Hilarius:BAAALgAECggJCwAAAA==.Hiraeth:BAAALgAECgQJBwAAAA==.',
Ho='Holydadbod:BAAALgAECgIJAgABLgAECgYJFwANAOEbAA==.Holyman:BAAALgADCgMJAwAAAA==.Holyshots:BAABLgAECn8gAAIFAAgJ6BD6KwCSAQAFAAgJ6BD6KwCSAQAAAA==.Howlinnbrews:BAAALgAFFAEJAgAAAA==.Howlinplague:BAAALgAECgUJCAAAAA==.',
Hu='Hulkhogan:BAAALgAECgcJEgAAAA==.Hunttal:BAAALgAECgEJAQAAAA==.',
Ia='Iamnoone:BAACLgAFFH8KAAIcAAMJnRdJIwC0AAAcAAMJnRdJIwC0AAAuAAQKfx4AAhwACAnuIbEVANQCABwACAnuIbEVANQCAAAA.',
Id='Idcaboutyou:BAAALgADCgkJBgAAAA==.Idrion:BAABLgAECn8WAAMDAAgJhhjvDgAgAgADAAgJhhjvDgAgAgAiAAEJiwxMNAAyAAAAAA==.',
Ig='Ignore:BAAALgADCgYJBgAAAA==.Igotdabrewz:BAABLgAECn8ZAAINAAcJUhZxEwBVAQANAAcJUhZxEwBVAQAAAA==.',
Il='Illorin:BAAALgADCgcJDgAAAA==.Illuvatari:BAAALgAECgEJAQAAAA==.',
In='Incindia:BAAALgADCgEJAQAAAA==.',
Io='Iobo:BAAALgAECgUJDgAAAA==.',
Ir='Ironhidez:BAAALgAECgYJEAAAAA==.',
Is='Isaarek:BAAALgAECgEJAQAAAA==.Ishiza:BAAALgADCggJDQAAAA==.',
Ja='Jabiso:BAAALgAECgUJCgAAAA==.Jacinto:BAAALgAFFAIJAwABLgAFFAUJDwAIALIhAA==.Jastia:BAAALgAECgQJDAAAAA==.Jayce:BAAALgADCgcJBwABLgAECgIJAgACAAAAAA==.',
Je='Jekelez:BAAALgADCgYJCQAAAA==.Jetblack:BAABLgAECn8bAAMKAAgJBRb6FwDoAQAKAAgJBRb6FwDoAQAUAAEJAADsbQA5AAAAAA==.Jezter:BAAALgAECgcJBgAAAA==.',
Jh='Jharlin:BAABLgAECn8UAAIFAAgJ7AiYQABIAQAFAAgJ7AiYQABIAQAAAA==.',
Jo='Joecephus:BAAALgAECgUJCQAAAA==.Joehex:BAABLgAECn8dAAIjAAgJVx6zAwBIAgAjAAgJVx6zAwBIAgAAAA==.Joulez:BAAALgADCgQJAgAAAA==.',
Ju='Judgematt:BAAALgAECgcJDAAAAA==.Justin:BAAALgAECgUJDgAAAA==.',
Ka='Kaevianda:BAAALgAECgUJCAAAAA==.Kageshootman:BAABLgAECn8XAAIOAAgJ0gwyBwByAQAOAAgJ0gwyBwByAQAAAA==.Kaleesh:BAACLgAFFH8FAAIkAAMJ+CS3AwDcAAAkAAMJ+CS3AwDcAAAuAAQKfx0AAiQACAmTJEcBAGgDACQACAmTJEcBAGgDAAAA.Kallux:BAABLgAECn8aAAIbAAgJ+xsDBgDMAQAbAAgJ+xsDBgDMAQAAAA==.Kananga:BAAALgAECgUJDQAAAA==.Karavira:BAAALgADCgcJDwAAAA==.Kasca:BAAALgADCgYJBgAAAA==.Kaybar:BAAALgADCgIJAgAAAA==.',
Ke='Kelindina:BAAALgAECgMJCgAAAA==.Kelindinas:BAAALgAECgQJBwAAAA==.Kevinshart:BAAALgAECgUJBQAAAA==.',
Kh='Khalli:BAAALgADCgcJGAAAAA==.',
Ki='Kieleron:BAAALgAECgUJCAAAAA==.Kierlessa:BAAALgAECgYJCQABLgAECggJJAAQADIcAA==.Kiermac:BAAALgAECgUJDgAAAA==.Kiermaxim:BAABLgAECn8kAAIQAAgJMhwYGwA6AgAQAAgJMhwYGwA6AgAAAA==.Kierzenkai:BAAALgAECgYJDAABLgAECggJJAAQADIcAA==.Kiragrande:BAABLgAECn8VAAIMAAgJkQ3EMAA1AQAMAAgJkQ3EMAA1AQAAAA==.Kiraneth:BAABLgAECn8eAAINAAcJHRH2EQBkAQANAAcJHRH2EQBkAQAAAA==.Kirial:BAAALgADCgcJBwAAAA==.Kiriku:BAAALgAECggJCAAAAA==.',
Kl='Klaysdnds:BAAALgADCggJEgAAAA==.',
Ko='Kobus:BAAALgADCgQJBAAAAA==.Korbinf:BAAALgAECgQJDAAAAA==.Kotok:BAAALgAECgQJBAAAAA==.',
Ku='Kungpownibs:BAAALgADCgUJBQAAAA==.',
La='Lagartista:BAAALgAECgEJAQAAAA==.Larplord:BAAALgAECgYJDQAAAA==.',
Ld='Ldyelphaba:BAAALgAECgUJCAAAAA==.',
Li='Lilchungus:BAAALgADCgIJAwAAAA==.Lindórie:BAAALgAECgEJAQAAAA==.Liturgy:BAAALgADCgMJAwAAAA==.',
Lo='Logankord:BAABLgAECn8dAAIgAAgJ4SCFAwCZAgAgAAgJ4SCFAwCZAgAAAA==.Lokeira:BAABLgAECn8jAAILAAgJGxs8KQDqAQALAAgJGxs8KQDqAQAAAA==.Lolded:BAAALgADCgEJAQAAAA==.Lono:BAABLgAECn8aAAIFAAgJfxFxMQB8AQAFAAgJfxFxMQB8AQAAAA==.Loop:BAAALgADCgMJAwAAAA==.Lorcana:BAAALgAECgEJAQAAAA==.Lorstus:BAAALgADCgYJBgAAAA==.',
Lu='Lucory:BAAALgAECgEJAQABLgAECgQJDwACAAAAAA==.Lumberjack:BAAALgADCgQJBgAAAA==.Luvbug:BAABLgAECn8WAAIHAAcJ2iLVDgAiAgAHAAcJ2iLVDgAiAgAAAA==.',
Ly='Lyara:BAACLgAFFH8MAAMLAAQJzyQTBQCZAQALAAQJzyQTBQCZAQAQAAIJ/QcyGQCPAAAuAAQKfxkAAwsACAkVIE4JAOICAAsACAkVIE4JAOICABAABAkeFv9aANgAAAAA.Lythos:BAABLgAECn8ZAAIbAAgJjBNoGwBzAQAbAAgJjBNoGwBzAQAAAA==.Lyu:BAAALgAFFAEJAQABLgAFFAQJDAALAM8kAA==.Lyuu:BAAALgAFFAIJBAABLgAFFAQJDAALAM8kAA==.',
['Lø']='Lørdøfßud:BAABLgAECn8bAAIgAAcJSx5/CwD0AQAgAAcJSx5/CwD0AQAAAA==.',
Ma='Macguffin:BAAALgADCgkJDgAAAA==.Machomans:BAAALgAECgEJAQABLgAECgYJDAACAAAAAA==.Malifae:BAABLgAECn8bAAISAAcJYSGWEwB3AgASAAcJYSGWEwB3AgAAAA==.Malimae:BAAALgADCgYJBgABLgAECgcJGwASAGEhAA==.Mankilla:BAAALgADCgUJBQAAAA==.Mansa:BAABLgAECn8XAAIlAAgJAxW3AwCrAQAlAAgJAxW3AwCrAQAAAA==.Mastamojo:BAABLgAECn8YAAIGAAcJYwUMKwD0AAAGAAcJYwUMKwD0AAAAAA==.Maulding:BAAALgADCgcJDgAAAA==.',
Mc='Mcmurphy:BAAALgAECgUJCQAAAA==.Mctanky:BAAALgAECgEJAgAAAA==.',
Me='Mechadragon:BAAALgADCgYJDwAAAA==.Meepmeep:BAAALgAECgQJBQAAAA==.Meissen:BAAALgAECgYJEQAAAA==.Melendaren:BAAALgADCgkJGwAAAA==.Melestaria:BAAALgAECgEJAQAAAA==.Meltara:BAAALgADCgUJBQAAAA==.Menonk:BAAALgADCgQJBQAAAA==.Meowandi:BAAALgAECgIJAgAAAA==.Merscy:BAAALgAECgcJEwAAAA==.Mertia:BAAALgAECgQJCgAAAA==.Messìah:BAAALgAECgYJDQAAAA==.Metamonster:BAABLgAECn8UAAMbAAYJiRCWFQDTAAAbAAYJ4g+WFQDTAAAIAAYJ9gTgjAB4AAAAAA==.Meåny:BAAALgAECgYJCQAAAA==.',
Mi='Mikimiku:BAAALgADCgUJBQAAAA==.Miniav:BAAALgADCgkJIQAAAA==.Mirko:BAAALgAECgYJDAAAAA==.Mistiah:BAAALgAECgEJAQAAAA==.Mistyjoe:BAAALgADCgMJAwAAAA==.',
Ml='Mladjo:BAAALgAECgYJDAAAAA==.',
Mo='Mockery:BAABLgAECn8hAAIRAAgJTxM2AgCsAQARAAgJTxM2AgCsAQAAAA==.Mokokniki:BAAALgADCggJCAAAAA==.Moneie:BAAALgADCgYJBgAAAA==.Monger:BAAALgADCgIJAgAAAA==.Monkyourself:BAAALgADCgYJCQAAAA==.Mooana:BAAALgADCgQJBAAAAA==.Moocowman:BAAALgAECgYJDgABLgAECggJCAACAAAAAA==.Moondo:BAAALgADCgYJBgAAAA==.Moone:BAAALgADCgYJBgAAAA==.Morticiá:BAAALgAECgYJCQAAAA==.Mortiferum:BAAALgADCgcJDQAAAA==.Mourningstar:BAACLgAFFH8HAAIIAAQJdR1NEwBVAQAIAAQJdR1NEwBVAQAuAAQKfxcAAggACAnJH0EUAAIDAAgACAnJH0EUAAIDAAEuAAUUBQkPAAgAsiEA.Mozaic:BAABLgAECn8hAAIjAAgJ3hR/BwDHAQAjAAgJ3hR/BwDHAQAAAA==.',
Mu='Mugrüíth:BAAALgADCggJFwAAAA==.',
My='Myragê:BAAALgADCgkJDQAAAA==.Myselia:BAAALgAECgYJCQAAAA==.Mystra:BAAALgAECgIJAgAAAA==.',
['Mè']='Mèany:BAAALgAECgUJBQABLgAECgYJCQACAAAAAA==.',
Na='Nad:BAAALgADCgQJBAAAAA==.Naek:BAAALgADCgkJHgAAAA==.Natawista:BAAALgADCgcJEgAAAA==.',
Ne='Necromus:BAAALgAECgUJDwAAAA==.Nekra:BAAALgADCgEJAQAAAA==.',
Ni='Nibbi:BAAALgADCgEJAQAAAA==.Nic:BAAALgADCgEJAQAAAA==.Nichtaire:BAAALgAECgcJEQAAAA==.Niem:BAABLgAECn8VAAImAAcJSSVQAwDbAgAmAAcJSSVQAwDbAgAAAA==.Nilyaf:BAAALgADCgQJBAAAAA==.',
No='Nocturnum:BAABLgAECn8fAAIcAAcJmhVfHQCDAQAcAAcJmhVfHQCDAQAAAA==.Notkorbin:BAAALgAECgIJAgAAAA==.Notreeus:BAAALgAECgEJAQAAAA==.Nowotrius:BAAALgADCgUJBQAAAA==.',
Nu='Numb:BAAALgAECgYJDAAAAA==.',
Ny='Nyxstryl:BAACLgAFFH8HAAIeAAQJRQ9PAABcAQAeAAQJRQ9PAABcAQAuAAQKfxsAAh4ACAktHi8BAPECAB4ACAktHi8BAPECAAAA.',
['Nô']='Nôkiaa:BAAALgAECgQJBgAAAA==.',
Ob='Obitus:BAAALgADCgEJAQABLgAECgYJCQACAAAAAA==.',
Od='Odahviing:BAAALgADCgQJBAAAAA==.Odin:BAAALgADCgYJBgAAAA==.Odium:BAAALgADCgMJAwABLgAECggJFwAOAD8gAA==.',
Oh='Ohuln:BAAALgADCgcJCAABLgAFFAUJFAAHAAwhAA==.',
Ol='Oldmage:BAAALgADCgUJBQAAAA==.Oldmongerpal:BAAALgADCgYJBgAAAA==.',
On='Onetwocowpow:BAABLgAECn8jAAIMAAgJ0RcLCgAMAgAMAAgJ0RcLCgAMAgAAAA==.',
Oo='Ooshiny:BAAALgAECgEJAQAAAA==.',
Or='Orclard:BAAALgAECgIJAgAAAA==.Ordanith:BAABLgAECn8nAAIFAAkJeCHQBADPAgAFAAkJeCHQBADPAgAAAA==.Orionn:BAACLgAFFH8KAAIHAAMJqR60CQAUAQAHAAMJqR60CQAUAQAuAAQKfy0AAgcACQnPI28GACYDAAcACQnPI28GACYDAAAA.Ornan:BAAALgAECgQJBAAAAA==.Ororo:BAAALgAECgIJAgAAAA==.',
Os='Osø:BAAALgAECgYJDAAAAA==.',
Ov='Oven:BAABLgAECn8gAAINAAgJVxYzCQDnAQANAAgJVxYzCQDnAQAAAA==.',
Pa='Pastaa:BAAALgAECgcJEwAAAA==.',
Ph='Phil:BAAALgAECgcJEwAAAA==.Phillio:BAAALgAECgQJBAAAAA==.Phoenixy:BAAALgADCgQJBAAAAA==.Phosphate:BAAALgAECgYJCQAAAA==.',
Pi='Pippins:BAAALgAECgEJAQAAAA==.',
Pl='Plunto:BAAALgADCgUJBQAAAA==.',
Po='Po:BAAALgAECgYJCQAAAA==.Portucala:BAAALgADCgYJCQAAAA==.',
Pr='Prarg:BAAALgADCgcJBwAAAA==.Praystation:BAAALgAECgUJCAAAAA==.',
Py='Pyral:BAAALgAECgYJDAAAAA==.',
Ra='Raekeshh:BAAALgAECggJDwAAAA==.Raelone:BAABLgAECn8UAAMKAAcJag+oTwABAQAKAAUJyAuoTwABAQAUAAUJ/RCrOwDFAAAAAA==.Rageofmommy:BAAALgADCgMJAwAAAA==.Raidoe:BAABLgAECn8iAAMMAAgJPBxhCAAvAgAMAAgJPBxhCAAvAgANAAEJ9QzPfgAxAAAAAA==.Raknaruk:BAAALgAECgEJAQAAAA==.Rakwiz:BAAALgADCgEJAQAAAA==.Rangérz:BAABLgAECn8aAAIHAAcJoBQbIwCQAQAHAAcJoBQbIwCQAQAAAA==.Rant:BAAALgAECgQJBwAAAA==.Rasa:BAAALgAECgUJCAAAAA==.Ratio:BAAALgADCgYJBgAAAA==.',
Re='Redshammy:BAAALgAECgYJCgAAAA==.Redward:BAABLgAECn8XAAIFAAcJNwkATAAnAQAFAAcJNwkATAAnAQAAAA==.',
Rh='Rhell:BAACLgAFFH8HAAIGAAMJhhbKEAD0AAAGAAMJhhbKEAD0AAAuAAQKfyoAAgYACQn5Hr4NAKoCAAYACQn5Hr4NAKoCAAAA.',
Ri='Rinche:BAABLgAECn8iAAMQAAgJ2BRQHwAeAQAQAAYJZRNQHwAeAQALAAgJ6gkmLQAQAQAAAA==.Rintche:BAAALgAECgIJAgAAAA==.',
Ro='Rolland:BAAALgAECgUJDQAAAA==.Rollf:BAAALgADCgUJBQAAAA==.Rootbeamxo:BAAALgADCgUJBgAAAA==.Rosefyre:BAAALgAECgYJCQAAAA==.',
Ru='Rudo:BAABLgAECn8YAAIHAAgJ0RUAFwDaAQAHAAgJ0RUAFwDaAQAAAA==.Rumproblem:BAAALgAECgYJCgAAAA==.Runnamuuk:BAABLgAECn8cAAIcAAgJXw6KJQBUAQAcAAgJXw6KJQBUAQAAAA==.Rush:BAAALgAECgEJAQAAAA==.',
Ry='Ryeger:BAABLgAECn8aAAIiAAgJQhOyBADcAQAiAAgJQhOyBADcAQAAAA==.',
['Rä']='Räsa:BAAALgAECgEJAQAAAA==.',
['Ró']='Róótbear:BAABLgAECn8fAAImAAcJTBO2CwAEAQAmAAcJTBO2CwAEAQAAAA==.',
Sa='Sadrobot:BAAALgAECgEJAgABLgAECgMJCgACAAAAAA==.Salfros:BAAALgADCgkJCwAAAA==.Sallydapally:BAAALgADCgYJBwAAAA==.Samovar:BAABLgAECn8bAAIFAAgJ/gjVPwBKAQAFAAgJ/gjVPwBKAQAAAA==.Sandbones:BAAALgAECgMJAwABLgAECggJIQARAE8TAA==.Sandraice:BAABLgAECn8YAAIFAAgJxgYwhwBsAQAFAAgJxgYwhwBsAQAAAA==.Sandwiches:BAAALgAECgYJEgAAAA==.Sanguinne:BAAALgAECgIJAgAAAA==.Sansami:BAABLgAECn8cAAITAAYJHBygJQDWAQATAAYJHBygJQDWAQAAAA==.Sarraloesh:BAAALgADCgIJAgAAAA==.Satoshi:BAAALgADCgMJAwAAAA==.',
Sc='Scalebagz:BAAALgAECggJEgAAAA==.Schism:BAAALgADCgkJDgAAAA==.',
Se='Selûne:BAAALgAECgMJBQAAAA==.Sentren:BAAALgADCgcJDAAAAA==.Senyorseven:BAAALgAECgQJCAAAAA==.Seo:BAAALgADCgUJBQAAAA==.Setresh:BAABLgAECn8nAAIVAAkJfhW8AwBYAgAVAAkJfhW8AwBYAgAAAA==.Severus:BAAALgADCgMJAwAAAA==.',
Sh='Shadöwsöng:BAABLgAECn8YAAIjAAcJqwY8FQDgAAAjAAcJqwY8FQDgAAAAAA==.Shaedelana:BAAALgAECgQJCgAAAA==.Shamrox:BAAALgAECgEJAQAAAA==.Shamwowhex:BAAALgAECggJCgAAAA==.Shangöh:BAAALgAECgYJBgABLgAECggJHgADADkfAA==.Shinygoat:BAAALgADCgIJAgABLgAECggJKAAJAAEiAA==.Shivyn:BAABLgAECn8dAAMLAAcJsQsuKAAuAQALAAcJsQsuKAAuAQAQAAEJFwW2jQAqAAAAAA==.Shoeman:BAAALgAECgEJAQAAAA==.Shokyo:BAAALgADCgUJBQAAAA==.Shoota:BAAALgAECgEJAQABLgAFFAUJFAAHAAwhAA==.Shugarion:BAAALgADCgUJAQAAAA==.Shàken:BAAALgADCgYJCgAAAA==.',
Si='Sibadeekay:BAABLgAECn8oAAMIAAgJfhqSGwDiAQAIAAgJfhqSGwDiAQAbAAUJrQ9RLgDMAAAAAA==.Sickkid:BAABLgAECn8bAAIgAAYJzhDFVABXAQAgAAYJzhDFVABXAQAAAA==.Siegekaiser:BAAALgADCgcJEwAAAA==.Silvershine:BAAALgAECgYJDwAAAA==.Silverwolf:BAAALgADCgcJBwAAAA==.Sindrya:BAAALgAECgMJBQAAAA==.',
Sk='Skoobastank:BAAALgADCgIJAgAAAA==.Skunkt:BAAALgADCgYJCAAAAA==.',
Sl='Slimeto:BAAALgAECgMJBAAAAA==.',
Sm='Smaeg:BAAALgAECgMJAwABLgAECgkJAgACAAAAAA==.Smeef:BAAALgAECgQJBAAAAA==.Smoothvelvet:BAAALgAECgYJDAAAAA==.',
Sn='Snays:BAAALgAECgYJEAAAAA==.Sneeger:BAAALgAECgIJAgAAAA==.Snuggles:BAAALgAECgQJDgAAAA==.',
So='Solidgen:BAAALgAECgEJAQAAAA==.Solobolo:BAAALgAECgQJBAABLgAECgQJBAACAAAAAA==.Sosreaper:BAAALgADCgYJCgAAAA==.',
Sp='Spadez:BAAALgAECggJEAAAAA==.Splortus:BAAALgAECgEJAQAAAA==.Sprath:BAAALgAECgEJAQAAAA==.Sprinkle:BAAALgAECgMJBwAAAA==.',
Ss='Ssraeshza:BAAALgAECgYJDAABLgAFFAUJDwAEADUYAA==.',
St='Staretra:BAABLgAECn8cAAMWAAgJwA/BHQAOAQAWAAcJEA7BHQAOAQAfAAMJlQM5MQBzAAAAAA==.Stficyhot:BAAALgADCgMJBgAAAA==.',
Su='Subsub:BAAALgADCgEJAQAAAA==.Sungjinwoo:BAAALgAECgYJCQAAAA==.Sunslap:BAAALgAECgYJEAAAAA==.Susanaa:BAAALgAECgUJBwAAAA==.',
Sy='Symana:BAABLgAECn8fAAIfAAgJwhpdFAA7AgAfAAgJwhpdFAA7AgAAAA==.Syradra:BAAALgAECgIJAgAAAA==.Sytka:BAAALgAECgUJBQAAAA==.',
['Sè']='Sèan:BAAALgADCgcJDAAAAA==.',
['Sì']='Sìlvertìger:BAAALgAECgYJCQAAAA==.',
Ta='Taadra:BAABLgAECn8hAAILAAgJ4xrRCABcAgALAAgJ4xrRCABcAgAAAA==.Talfuki:BAAALgADCgUJBQAAAA==.Taliliia:BAAALgAECgEJAQAAAA==.Talkova:BAAALgAECgYJDgAAAA==.Talohae:BAAALgAECggJEgAAAA==.Talona:BAAALgAECgQJBAABLgAFFAQJBwAeAEUPAA==.Tandaan:BAAALgADCgkJCQABLgAECggJDwACAAAAAA==.Tanjent:BAAALgAECgQJCgAAAA==.Tapio:BAAALgAECgUJDwAAAA==.Tatsuma:BAAALgADCgcJBwABLgAECgYJDQACAAAAAA==.Tatsumå:BAAALgAECgYJDQAAAA==.',
Te='Terp:BAAALgAECgMJBgAAAA==.',
Th='Thalrissa:BAAALgAECgMJAwAAAA==.Thort:BAAALgAECgMJAwAAAA==.Thuglifé:BAAALgADCgYJDQAAAA==.',
Ti='Tia:BAAALgAECgEJAQAAAA==.Tidemaiden:BAAALgAECgYJEAAAAA==.Tiktac:BAAALgADCgUJCAAAAA==.Tinynflaccid:BAAALgADCgMJAwAAAA==.Tipsymancer:BAABLgAECn8jAAITAAgJERy9BQBIAgATAAgJERy9BQBIAgAAAA==.Tirael:BAAALgAECgYJBQAAAA==.',
To='Tomö:BAAALgAECgIJAgAAAA==.Touji:BAAALgADCgcJDAAAAA==.',
Tr='Treesus:BAABLgAECn8aAAISAAgJ2RWNGwAmAgASAAgJ2RWNGwAmAgAAAA==.Trinket:BAAALgADCgEJAQABLgAECggJGAAHANEVAA==.Trollroom:BAAALgADCgkJCQAAAA==.Truemagi:BAAALgAECgIJAQAAAA==.',
Tw='Twinklehoofs:BAAALgAECgUJBgAAAA==.Twiztid:BAAALgADCgYJCAAAAA==.',
Ty='Tyrethal:BAAALgADCgcJBwAAAA==.',
['Tñ']='Tñer:BAABLgAECn8aAAQPAAgJ1COBCwCLAgAPAAgJWyGBCwCLAgARAAMJ5CPEAwBBAQAnAAEJTQ0XDwA8AAAAAA==.',
Ul='Ulahwekeheia:BAABLgAECn8YAAIDAAgJyBjOJwAWAgADAAgJyBjOJwAWAgAAAA==.',
Ur='Uruloki:BAAALgAFFAIJAgAAAA==.',
Us='Usidore:BAAALgADCgcJBwAAAA==.',
Va='Vainin:BAAALgAECgQJBgAAAA==.Valle:BAAALgAECgUJCQAAAA==.Valry:BAAALgADCgIJAgAAAA==.Vanilla:BAAALgADCgQJBAABLgAFFAMJCAATAAsKAA==.Variable:BAAALgADCgEJAQAAAA==.Vashdin:BAAALgAECgUJDwAAAA==.',
Ve='Vectorvega:BAAALgAECgEJAQABLgAECggJGAAHANEVAA==.Veicilia:BAAALgAECgMJAwAAAA==.Velashis:BAABLgAECn8VAAIDAAgJNRf9LwDsAQADAAgJNRf9LwDsAQAAAA==.Velshariel:BAAALgADCgUJBQAAAA==.Vermin:BAAALgAECggJCAAAAA==.',
Vi='Viable:BAAALgAECgQJBgAAAA==.Vibes:BAAALgADCgkJEQAAAA==.Victorvega:BAAALgAECgMJAwABLgAECggJGAAHANEVAA==.Vilt:BAAALgADCgMJAwAAAA==.Visandar:BAAALgAECgkJDQAAAA==.Vivif:BAACLgAFFH8GAAMMAAMJWAgSEgCKAAAMAAMJWAgSEgCKAAANAAEJlQ1xEQBOAAAuAAQKfxUAAw0ACQnzHBEQAH8CAA0ACAmkHBEQAH8CAAwABQnwHwMeABABAAAA.Vivillian:BAAALgAECgEJAQAAAA==.Vixsin:BAAALgADCgQJCwAAAA==.',
Vo='Vodmos:BAAALgAECgEJAQAAAA==.Vordilina:BAAALgAECggJEwAAAA==.',
Vr='Vresim:BAABLgAECn8XAAQYAAgJKRnuEwAGAgAYAAgJKRnuEwAGAgAaAAQJuxj1DwBUAAAZAAEJyANrTAApAAAAAA==.',
Vu='Vuginhood:BAAALgADCgEJAgAAAA==.Vugnus:BAAALgAECgUJDwAAAA==.',
Vy='Vynarras:BAAALgAECgcJDgAAAA==.',
['Vé']='Véxx:BAABLgAECn8WAAQJAAYJ5hnkBwA2AQAJAAUJth7kBwA2AQAdAAUJYAitQgDtAAAcAAEJdAGN9QAZAAAAAA==.',
Wa='Wannan:BAAALgADCgYJCQAAAA==.Wardamon:BAAALgADCgYJBgABLgAECgEJAgACAAAAAA==.Warihor:BAABLgAECn8gAAMgAAgJjQihHABLAQAgAAgJawihHABLAQAhAAcJuga4FADVAAAAAA==.',
We='Weezle:BAAALgAECgMJBgAAAA==.Westrin:BAABLgAECn8dAAIeAAkJZh9GAwBsAgAeAAkJZh9GAwBsAgAAAA==.',
Wi='Wife:BAAALgAECgIJAgAAAA==.Wiz:BAAALgADCgcJDAAAAA==.',
Wo='Worgendork:BAAALgAECgkJBgAAAA==.',
Wr='Wrangler:BAAALgAECgcJBAAAAA==.',
Wy='Wyndeline:BAAALgAECgMJBgAAAA==.',
Xa='Xarrie:BAAALgADCgMJCQAAAA==.',
Xc='Xc:BAAALgADCgcJBwAAAA==.',
Xo='Xorxel:BAAALgAECgEJAQAAAA==.',
Ya='Yacob:BAAALgAECggJEQAAAA==.',
Yg='Yggrasdil:BAABLgAECn8eAAIDAAgJOR/MBQC/AgADAAgJOR/MBQC/AgAAAA==.',
Yh='Yhwach:BAABLgAFFH8FAAIbAAMJewkcDwCwAAAbAAMJewkcDwCwAAAAAA==.',
Yi='Yikes:BAAALgADCgEJAQAAAA==.',
Ym='Ymir:BAAALgAECgcJDQABLgAECgMJBAACAAAAAA==.',
Yo='Yolasses:BAAALgAECgYJEAAAAA==.',
Yu='Yuie:BAAALgAECgQJBQAAAA==.Yukitaiga:BAAALgAECgQJCAABLgABCgMJAwACAAAAAA==.Yule:BAAALgAECgQJBAAAAA==.',
Za='Zaeden:BAABLgAECn8ZAAIMAAYJxR6aFgANAgAMAAYJxR6aFgANAgAAAA==.Zaftdh:BAABLgAECn8RAAIcAAgJdA/kcwBJAQAcAAgJdA/kcwBJAQAAAA==.Zaha:BAABLgAECn8eAAIPAAYJ2CKiXAAkAgAPAAYJ2CKiXAAkAgAAAA==.Zaidane:BAAALgADCgYJBgAAAA==.Zarov:BAAALgADCgQJBAAAAA==.Zarthan:BAAALgAECgEJAQAAAA==.',
Zd='Zdps:BAAALgAECgQJAgAAAA==.',
Ze='Zem:BAABLgAECn8ZAAIgAAcJTxlqDwDCAQAgAAcJTxlqDwDCAQAAAA==.Zeroultra:BAABLgAECn8YAAIgAAYJohbUQQCdAQAgAAYJohbUQQCdAQAAAA==.Zeusmos:BAABLgAECn8bAAINAAgJmyTLAQDaAgANAAgJmyTLAQDaAgAAAA==.',
Zi='Zithenex:BAAALgAECgUJDwAAAA==.',
Zw='Zwar:BAAALgADCggJEAAAAA==.',
Zy='Zynsis:BAAALgADCgYJCQAAAA==.',
['Ál']='Álister:BAAALgAECgEJAQAAAA==.',
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
