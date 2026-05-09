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

local lookup = {'Rogue-Subtlety','Unknown-Unknown','Druid-Restoration','Paladin-Protection','Paladin-Retribution','Paladin-Holy','Hunter-BeastMastery','DeathKnight-Unholy','DemonHunter-Vengeance','Warlock-Demonology','Shaman-Restoration','Monk-Mistweaver','Monk-Windwalker','Shaman-Elemental','Hunter-Marksmanship','Mage-Frost','Priest-Holy','Mage-Arcane','Druid-Balance','Monk-Brewmaster','Warlock-Destruction','Hunter-Survival','Priest-Shadow','DeathKnight-Frost','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Warrior-Fury','DeathKnight-Blood','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Affliction','Warrior-Arms','Warrior-Protection','Druid-Feral','Shaman-Enhancement','Rogue-Assassination','Druid-Guardian','Mage-Fire',}
local provider = {region='US',realm='Zangarmarsh',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aaminae:BAABLgAECn8bAAIBAAgJvxEcDwCzAQABAAgJvxEcDwCzAQAAAA==.',
Ab='Abora:BAAALgADCgUJBwABLgAECgEJAQACAAAAAA==.Abracadaver:BAAALgAECgQJBAAAAA==.Abracastabya:BAAALgAECggJDwAAAA==.Abraxys:BAAALgADCgIJAgAAAA==.',
Ad='Adachï:BAAALgAECgYJEwABLgAECgkJJwADAGoeAA==.Adevil:BAAALgADCgcJCAAAAA==.Adune:BAAALgADCgEJAQABLgAECgYJEAACAAAAAA==.',
Ae='Aedar:BAAALgAECgYJDQAAAA==.Aethlin:BAABLgAECn8bAAMEAAgJGhrvCAC6AQAEAAcJzBnvCAC6AQAFAAcJlBT5nQBDAQAAAA==.Aeturnas:BAABLgAECn8hAAIGAAgJ4h9FBgC8AgAGAAgJ4h9FBgC8AgAAAA==.',
Ag='Agralesia:BAAALgADCgkJCQAAAA==.',
Al='Alanima:BAAALgAECgEJAQAAAA==.Aldky:BAAALgADCgkJDgAAAA==.Aliana:BAAALgAECgIJAgAAAA==.Allindis:BAAALgAECgYJCQABLgAECggJIAADALkZAA==.Allypally:BAAALgADCgMJAwAAAA==.Alphamage:BAAALgADCgMJAwAAAA==.Alphamonk:BAAALgAECgYJCgAAAA==.Alros:BAABLgAECn8lAAIHAAgJkCI2BwC+AgAHAAgJkCI2BwC+AgAAAA==.Alslock:BAAALgADCgIJAgAAAA==.Alvaah:BAAALgADCgUJBQAAAA==.',
Am='Amardyton:BAAALgAECgUJBQAAAA==.',
Ar='Archon:BAAALgADCgQJBAABLgAECgIJAgACAAAAAA==.Arctica:BAAALgADCgQJBAAAAA==.Arette:BAAALgAECgIJAgAAAA==.Arkades:BAAALgAECgYJEwAAAA==.Arkshade:BAABLgAECn8aAAIIAAYJ0w64XgAnAQAIAAYJ0w64XgAnAQAAAA==.Arlia:BAAALgAECgQJCAAAAA==.Armorup:BAAALgAECgUJCAAAAA==.Artaz:BAAALgAECgQJAwABLgAECggJKAAJAAAiAA==.Aryn:BAAALgADCgQJBAAAAA==.',
As='Ashez:BAAALgADCgMJAgABLgAECgQJBQACAAAAAA==.Ashor:BAAALgAECgEJAQAAAA==.Asmo:BAAALgADCggJGAAAAA==.Astarii:BAAALgAECgEJBAAAAA==.Asterica:BAABLgAECn8uAAIKAAkJOBYJHwD2AQAKAAkJOBYJHwD2AQAAAA==.',
At='Atormentor:BAAALgADCgIJAQAAAA==.',
Au='Auggystyle:BAAALgAECgYJCwAAAA==.Auriaza:BAABLgAECn8YAAILAAYJ+A10UwA4AQALAAYJ+A10UwA4AQAAAA==.',
Av='Averynicole:BAAALgAECgUJEQAAAA==.',
Aw='Awasjr:BAABLgAECn8aAAIHAAgJTB33EgA5AgAHAAgJTB33EgA5AgAAAA==.',
Ay='Ayano:BAAALgAECgYJDgAAAA==.',
['Añ']='Añimorph:BAAALgAECgQJBQAAAA==.',
Ba='Balazar:BAAALgAECgYJCgAAAA==.Balthïer:BAAALgAECgUJDQABLgAECgkJJwADAGoeAA==.Bark:BAAALgAECgYJBgAAAA==.',
Be='Beanfist:BAAALgADCgkJDgAAAA==.Bearhug:BAABLgAECn8mAAMMAAgJrhZeIACwAQAMAAcJrRheIACwAQANAAYJhAh3QgANAQABLgAFFAQJBQAOAEsJAA==.Bearshock:BAABLgAFFH8FAAMOAAQJSwniHwCjAAAOAAMJJAHiHwCjAAALAAEJTAA2RgAjAAAAAA==.Beasty:BAABLgAECn8XAAIPAAYJ9w7TRABCAQAPAAYJ9w7TRABCAQAAAA==.Beatriixx:BAAALgAECgEJAQAAAA==.Bee:BAABLgAECn8nAAIEAAkJTCPIAAD+AgAEAAkJTCPIAAD+AgAAAA==.Beeb:BAAALgAECgUJDgABLgAECgkJJwAEAEwjAA==.Beefisting:BAAALgAECgQJBwABLgAECgkJJwAEAEwjAA==.Belardor:BAAALgAECgkJBwAAAA==.Beliara:BAAALgAECgUJCQAAAA==.Bellamere:BAAALgADCgkJCAAAAA==.Beverage:BAAALgAECgEJAQAAAA==.',
Bi='Bionarra:BAABLgAECn8iAAIQAAgJkxSANADPAQAQAAgJkxSANADPAQAAAA==.Bishopwr:BAAALgAECggJEwAAAA==.Bittertøfu:BAABLgAECn8eAAIOAAcJfQacLgD7AAAOAAcJfQacLgD7AAAAAA==.',
Bl='Blackwidöw:BAAALgAECgIJBgAAAA==.Blaire:BAAALgADCgcJAQAAAA==.Blitê:BAAALgADCgUJBQABLgADCgkJDQACAAAAAA==.',
Bm='Bmpfrostie:BAAALgAECgcJDwAAAA==.',
Bo='Bocay:BAAALgADCgEJAQABLgAECggJHAARAGEcAA==.Bohica:BAAALgAECgYJCgAAAA==.Booker:BAAALgADCgUJBQAAAA==.Boonn:BAAALgAECggJEQAAAA==.Boorne:BAAALgADCgQJBAAAAA==.',
Br='Brakug:BAABLgAECn8qAAMQAAkJayKaGABXAgAQAAkJayKaGABXAgASAAEJBw7RHgAzAAAAAA==.Braywyat:BAAALgADCgUJBQAAAA==.Breck:BAAALgAECgIJAgAAAA==.Brekk:BAAALgAFFAEJAQAAAA==.Brem:BAABLgAECn8WAAISAAgJahkeBAASAgASAAgJahkeBAASAgAAAA==.Bretagnesse:BAABLgAECn8UAAITAAgJ2wXBJAAVAQATAAgJ2wXBJAAVAQAAAA==.Briara:BAAALgADCgkJEAAAAA==.Brittyy:BAAALgADCgUJBgAAAA==.Broknüs:BAAALgADCgEJAQAAAA==.Broníx:BAAALgAECgEJAwAAAA==.Bropeep:BAABLgAECn8lAAIIAAcJcSNVEgBpAgAIAAcJcSNVEgBpAgAAAA==.',
Bu='Bullshott:BAABLgAECn8VAAIHAAgJmxsuGQAIAgAHAAgJmxsuGQAIAgAAAA==.Bum:BAABLgAECn8mAAMTAAkJsh/2BABRAwATAAkJsh/2BABRAwADAAEJ0xCL0QAtAAAAAA==.Bumagak:BAAALgADCgMJAwAAAA==.Bundles:BAAALgADCgYJBgAAAA==.Butts:BAAALgAECgIJAgAAAA==.',
By='Bylun:BAAALgAECgkJCAAAAA==.',
['Bè']='Bèrtim:BAAALgAECgQJBQAAAA==.',
Ca='Caeruleum:BAAALgAECgQJBQAAAA==.Calyen:BAAALgAECgYJBgABLgAECgYJGwAUAA0JAA==.Canmm:BAAALgAECgIJAgAAAA==.Carartha:BAABLgAECn8iAAIFAAgJ7gZNXQA1AQAFAAgJ7gZNXQA1AQAAAA==.Carrots:BAAALgAECgYJEwAAAA==.Cashmachine:BAABLgAECn8iAAIHAAgJgyAsDAB+AgAHAAgJgyAsDAB+AgAAAA==.Catfight:BAABLgAECn8VAAIEAAYJJBEgFwDhAAAEAAYJJBEgFwDhAAAAAA==.',
Ch='Chagall:BAAALgADCgcJEAAAAA==.Charcoal:BAABLgAECn8rAAMKAAkJchhpFwAnAgAKAAkJchhpFwAnAgAVAAEJAABfZwBBAAAAAA==.Charlié:BAAALgADCggJCAAAAA==.Chasebakes:BAACLgAFFH8HAAQHAAMJNh7MMgC5AAAHAAIJQBzMMgC5AAAPAAEJISIsIwBlAAAWAAEJzA/wGgBWAAAuAAQKfxcABA8ACAlEILkYAGYCAA8ACAmlH7kYAGYCAAcAAwlfGdRiAOgAABYAAwkkGMEsAJIAAAAA.Cheesecake:BAABLgAECn8cAAIVAAYJvxC4CwAZAQAVAAYJvxC4CwAZAQAAAA==.Choks:BAAALgAECgUJDgAAAA==.Chromie:BAAALgADCgMJAwAAAA==.Chubbycat:BAAALgAECgcJDQAAAA==.Chuggz:BAABLgAECn8fAAIUAAgJoRh/CwAKAgAUAAgJoRh/CwAKAgAAAA==.Chéfboyrlee:BAACLgAFFH8RAAIXAAYJghjEBACUAQAXAAYJghjEBACUAQAuAAQKfy0AAhcACQlxHxYHABkDABcACQlxHxYHABkDAAAA.',
Ci='Cizmac:BAAALgAECgEJAQAAAA==.',
Cn='Cnari:BAAALgADCgEJAQAAAA==.',
Co='Corruptdata:BAAALgADCgYJBwAAAA==.Cownado:BAABLgAECn8bAAIUAAYJDQldLgDjAAAUAAYJDQldLgDjAAAAAA==.',
Cr='Crouton:BAAALgADCgkJCgAAAA==.',
Cy='Cybelem:BAABLgAECn8qAAIOAAkJ7R1PBAC5AgAOAAkJ7R1PBAC5AgAAAA==.Cyfelen:BAAALgADCgcJBwAAAA==.Cynleel:BAAALgAECgYJCgAAAA==.Cyris:BAAALgAECgMJAwAAAA==.',
Da='Damondafel:BAAALgAECgEJAQAAAA==.Damonstyle:BAAALgAECgEJAQAAAA==.Dandistyle:BAABLgAECn8bAAMUAAkJdx0iBACvAgAUAAkJbh0iBACvAgANAAEJchKrfAAzAAAAAA==.Darkshe:BAAALgAECgEJAgAAAA==.Darrot:BAAALgADCgUJBQAAAA==.Daz:BAAALgADCgUJBQAAAA==.',
De='Deadgeinside:BAAALgADCgIJAgAAAA==.Deathnom:BAAALgADCgEJAQAAAA==.Deepssham:BAAALgAECgMJAwAAAA==.Deeviant:BAAALgAECgYJCQAAAA==.Defend:BAAALgAECgYJBgABLgAFFAMJCwAUACQKAA==.Delrager:BAABLgAECn8YAAIBAAYJSiT6CAATAgABAAYJSiT6CAATAgAAAA==.Derat:BAAALgAECggJCAAAAA==.',
Di='Dibbydab:BAABLgAECn8UAAILAAcJ0RKlLABkAQALAAcJ0RKlLABkAQAAAA==.',
Dj='Django:BAABLgAECn8tAAMTAAkJFiKlAQAiAwATAAkJFiKlAQAiAwADAAIJkAbDiQBCAAAAAA==.Djatalon:BAAALgAECgUJDAAAAA==.Djderpyderpy:BAAALgAECgUJBwAAAA==.Djehrtey:BAAALgADCgYJCgAAAA==.Djin:BAAALgAECgMJBAABLgAECggJHwANAAobAA==.Djinni:BAABLgAECn8fAAMNAAgJChtXCQAnAgANAAgJTBpXCQAnAgAUAAYJ4xtvKADDAQAAAA==.',
Do='Doffy:BAAALgAECgEJAQAAAA==.Doodle:BAABLgAECn8WAAMYAAYJfBjABQDVAQAYAAYJfBjABQDVAQAIAAMJsA16/QCAAAAAAA==.Dorlen:BAAALgADCgYJCgAAAA==.',
Dr='Dracnahr:BAABLgAECn8XAAQZAAcJNxlOCADkAQAZAAcJNxlOCADkAQAaAAQJuwynMwDUAAAbAAEJAAB5PAA8AAAAAA==.Dracpriest:BAAALgADCgQJBAAAAA==.Draffut:BAAALgADCgkJGQAAAA==.Dramaticus:BAAALgADCgEJAQAAAA==.Draul:BAAALgAECgEJAQAAAA==.Drfear:BAAALgAECgMJAwAAAA==.Drifabell:BAAALgADCgcJEgAAAA==.',
Du='Dumblegear:BAABLgAECn8VAAMQAAcJFBKOVgBpAQAQAAcJFBKOVgBpAQASAAEJbQYzIAAvAAAAAA==.Durgè:BAAALgAECgUJBQABLgAECggJIwAcAMUfAA==.',
Dy='Dychi:BAAALgAECgYJBwAAAA==.Dypndots:BAAALgAECgYJBwABLgAECgYJBwACAAAAAA==.Dyvoke:BAAALgADCgEJAQABLgAECgYJBwACAAAAAA==.',
Dz='Dzi:BAAALgADCgIJAgAAAA==.',
['Dä']='Däbeëfmäster:BAAALgADCgQJBgAAAA==.Dädärkbeëf:BAAALgADCgcJBwAAAA==.',
Ed='Edinna:BAABLgAECn8ZAAMQAAgJRQ6MRQCWAQAQAAgJswyMRQCWAQASAAQJTQoSEADBAAAAAA==.',
Ek='Ekatrina:BAAALgADCgkJDgAAAA==.',
El='Elara:BAAALgADCgQJBAAAAA==.Elessedil:BAAALgAECgYJCgAAAA==.Ellariia:BAAALgADCgYJBgAAAA==.Ellemystic:BAAALgAECgEJAQAAAA==.Elyriana:BAABLgAECn8bAAIDAAgJciJLCQC0AgADAAgJciJLCQC0AgAAAA==.',
Em='Emberzz:BAAALgAECgUJCAAAAA==.Emeralda:BAAALgAECgEJAQAAAA==.Emila:BAEALgAECgYJEAAAAA==.Emokilla:BAAALgADCgkJHAAAAA==.Empusia:BAAALgADCgMJAwAAAA==.Emriq:BAAALgAECgYJCgAAAA==.',
En='Encounter:BAAALgADCgMJAwAAAA==.Enrique:BAACLgAFFH8LAAIFAAQJjBurEQBgAQAFAAQJjBurEQBgAQAuAAQKfy0AAgUACQnbHDoPAIMCAAUACQnbHDoPAIMCAAAA.',
Er='Erazath:BAAALgAECgEJAQABLgAECggJGQAdAI4TAA==.Erufuyokai:BAAALgADCgUJBQAAAA==.Erusdh:BAAALgADCgIJAgAAAA==.',
Es='Esha:BAAALgADCgkJDgAAAA==.Estanna:BAAALgAECgkJAgAAAA==.',
Ev='Evolv:BAAALgAECgkJCAAAAA==.Evöö:BAAALgADCgUJAwAAAA==.',
Ey='Eysis:BAAALgADCgUJBQAAAA==.',
Fa='Faerdya:BAAALgAECgYJDgAAAA==.Falar:BAAALgAECgYJCQAAAA==.Faval:BAAALgAECggJCAABLgAECggJKAAJAAAiAA==.Favel:BAABLgAECn8oAAMJAAgJACJOAQAcAwAJAAgJ4iFOAQAcAwAeAAgJ0QqPPABFAQAAAA==.',
Fc='Fckvwls:BAAALgADCgYJCgAAAA==.',
Fe='Fearlesfreep:BAABLgAECn8oAAIHAAgJkRZwHgDlAQAHAAgJkRZwHgDlAQAAAA==.Febz:BAABLgAECn8eAAIQAAgJbBsmMACyAgAQAAgJbBsmMACyAgAAAA==.Febzy:BAAALgAECgQJBQAAAA==.Felatonin:BAAALgAECgcJDQAAAA==.Felfüry:BAABLgAECn8eAAMfAAgJsAqiGAAcAQAfAAcJ6wuiGAAcAQAJAAcJ/gQVEQCxAAAAAA==.Fenixshaw:BAAALgADCgkJHQAAAA==.Feudal:BAAALgAECggJEAAAAA==.Feyd:BAAALgAECgYJDQAAAA==.',
Fi='Fin:BAAALgADCgcJEAABLgAECgQJBQACAAAAAA==.Finella:BAAALgAECgMJBAAAAA==.Finneas:BAAALgADCgUJBQABLgAECgYJEwACAAAAAA==.Firefire:BAAALgAECgMJAwAAAA==.Fistkug:BAAALgAECgIJAgABLgAECgkJKgAQAGsiAA==.Fistsofurry:BAAALgAECgQJBAABLgAECgMJBAACAAAAAA==.',
Fj='Fjeighty:BAAALgAECgYJEwAAAA==.',
Fo='Foggpy:BAACLgAFFH8HAAMgAAQJdg3zAQD1AAAgAAMJBBDzAQD1AAAKAAQJnwOlOwDmAAAuAAQKfyIABCAACAkPInUEADYCACAABwl+JHUEADYCAAoABgkNG7dXAMABABUABgliGQ0fAFgBAAAA.',
Fr='Frederich:BAAALgAECgMJAwAAAA==.Freyke:BAAALgADCgUJBQAAAA==.Frostlicious:BAAALgADCgEJAQAAAA==.Frostybear:BAABLgAECn8uAAIQAAkJExLmJQAMAgAQAAkJExLmJQAMAgAAAA==.Frostydk:BAAALgAECgcJBwAAAA==.Fröstmöurne:BAABLgAECn8hAAIdAAcJYAdxHwDHAAAdAAcJYAdxHwDHAAAAAA==.',
['Fé']='Félindra:BAAALgADCgQJAgAAAA==.',
Ga='Galaythien:BAAALgADCgkJHgAAAA==.Garai:BAAALgADCgYJBgAAAA==.Garrex:BAAALgAECgEJAQABLgAFFAMJDAAeAEQaAA==.',
Ge='Geret:BAABLgAECn8iAAIFAAgJdxO3LgDCAQAFAAgJdxO3LgDCAQAAAA==.Gezabelle:BAAALgADCgIJAgAAAA==.',
Gi='Gigihadid:BAAALgADCgYJBgAAAA==.',
Gl='Glitchy:BAABLgAECn8sAAITAAkJ9xwGBQCdAgATAAkJ9xwGBQCdAgAAAA==.Glokraz:BAAALgAECgcJAQAAAA==.Glowbark:BAAALgADCgcJBwAAAA==.Glumpto:BAAALgAECgQJBwAAAA==.',
Go='Goingtogetu:BAABLgAECn8sAAIEAAkJESBbAQDPAgAEAAkJESBbAQDPAgAAAA==.Gold:BAAALgAECgIJAgAAAA==.Goldfarmr:BAABLgAECn8kAAIRAAkJPh8XBADbAgARAAkJPh8XBADbAgAAAA==.Goldshocker:BAAALgAECgQJBQAAAA==.Golduwu:BAAALgAECgEJAQAAAA==.Gorlami:BAAALgAECgcJBgAAAA==.',
Gr='Greeley:BAABLgAECn8hAAIPAAkJryKLAAAoAwAPAAkJryKLAAAoAwAAAA==.Gregdapro:BAABLgAECn8qAAIdAAgJZSEeBQDxAgAdAAgJZSEeBQDxAgAAAA==.Gregnstone:BAABLgAECn8ZAAIGAAgJsBglGQDCAQAGAAgJsBglGQDCAQABLgAECggJKgAdAGUhAA==.Grimmnstrous:BAAALgADCgEJAQABLgAFFAMJBQAaAH4GAA==.',
Gu='Gunnhunter:BAAALgAECgYJDQABLgAFFAUJFQAcANEcAA==.Gunnyal:BAABLgAECn8UAAMhAAYJKw7SFQAKAQAhAAYJKw7SFQAKAQAcAAQJsQczQAC/AAAAAA==.',
Gw='Gwencthlan:BAAALgAECgEJAwAAAA==.',
Gy='Gyathew:BAABLgAECn8lAAIOAAkJeiFxAgD9AgAOAAkJeiFxAgD9AgAAAA==.',
Ha='Haerin:BAAALgADCgEJAgABLgADCgYJCQACAAAAAA==.Hagunn:BAACLgAFFH8VAAMcAAUJ0RwWCABhAQAcAAUJ0RwWCABhAQAhAAEJNAELDgA8AAAuAAQKfzMAAxwACQlHIhQFAKgCABwACQk+IhQFAKgCACEAAwldHFQXAP0AAAAA.Hakyahi:BAAALgADCggJCAAAAA==.Hank:BAAALgADCgYJBgAAAA==.Harkin:BAABLgAECn8dAAIFAAgJXQ9lRAB4AQAFAAgJXQ9lRAB4AQAAAA==.Harnzak:BAAALgADCgEJAQABLgAECgQJBAACAAAAAA==.Hatchett:BAAALgAECgEJAQAAAA==.',
He='Heatfrezze:BAAALgAECgYJBgAAAA==.Heresurstick:BAABLgAECn8aAAIOAAcJXQvnJgAkAQAOAAcJXQvnJgAkAQAAAA==.Hermioné:BAAALgADCgUJBQAAAA==.Hevy:BAABLgAECn8nAAIeAAgJJxfiHADcAQAeAAgJJxfiHADcAQAAAA==.',
Hi='Hilarius:BAAALgAECggJCwAAAA==.Hiraeth:BAAALgAECgQJBwAAAA==.',
Ho='Holydadbod:BAAALgAECgIJAwABLgAECggJHwANAAobAA==.Holyman:BAAALgADCgMJAwAAAA==.Holyshots:BAABLgAECn8pAAIFAAkJOhIiJADzAQAFAAkJOhIiJADzAQAAAA==.Howlinnbrews:BAAALgAFFAIJBAAAAA==.Howlinplague:BAAALgAECgUJCAAAAA==.',
Hu='Hulkhogan:BAABLgAECn8UAAIiAAcJGh8cEgDmAQAiAAcJGh8cEgDmAQAAAA==.Hunttal:BAAALgAECgEJAQAAAA==.',
Ia='Iamnoone:BAACLgAFFH8MAAIeAAMJRBoyLgD4AAAeAAMJRBoyLgD4AAAuAAQKfx4AAh4ACAnuIa0VANQCAB4ACAnuIa0VANQCAAAA.',
Id='Idcaboutyou:BAAALgADCgkJBgAAAA==.Idrion:BAABLgAECn8ZAAMDAAgJihhaFgASAgADAAgJihhaFgASAgAjAAIJ1hJnIgBMAAAAAA==.',
Ig='Ignore:BAAALgADCgYJBgAAAA==.Igotdabrewz:BAABLgAECn8ZAAINAAcJVBbYGgBNAQANAAcJVBbYGgBNAQAAAA==.',
Il='Illorin:BAAALgADCgcJDgAAAA==.Illuvatari:BAAALgAECgEJAQAAAA==.',
In='Incindia:BAAALgADCgEJAQAAAA==.',
Io='Iobo:BAABLgAECn8UAAIWAAYJvg9LGQA+AQAWAAYJvg9LGQA+AQAAAA==.',
Ir='Ironhidez:BAABLgAECn8XAAIFAAcJuggpaQAbAQAFAAcJuggpaQAbAQAAAA==.',
Is='Isaarek:BAAALgAECgcJCQAAAA==.Ishiza:BAAALgADCggJDQAAAA==.',
Ja='Jabiso:BAAALgAECgUJDQAAAA==.Jacinto:BAAALgAFFAIJAwABLgAFFAUJFAAIALAhAA==.Jastia:BAAALgAECgUJDgAAAA==.Jayce:BAAALgADCgcJBwABLgAECgIJAgACAAAAAA==.',
Je='Jekelez:BAAALgADCgYJCQAAAA==.Jetblack:BAABLgAECn8fAAMKAAgJxhfOHAADAgAKAAgJxhfOHAADAgAVAAEJAADsbQA5AAAAAA==.Jezter:BAAALgAECgcJBgAAAA==.',
Jh='Jharlin:BAABLgAECn8aAAIFAAgJCgr4UQBRAQAFAAgJCgr4UQBRAQAAAA==.',
Jo='Joecephus:BAAALgAECgYJDgAAAA==.Joehex:BAABLgAECn8lAAIiAAgJ/B4iBQBWAgAiAAgJ/B4iBQBWAgAAAA==.Joulez:BAAALgADCgQJAgAAAA==.',
Ju='Judgematt:BAAALgAECgcJDQAAAA==.Justin:BAABLgAECn8UAAIhAAYJzRcYDQBwAQAhAAYJzRcYDQBwAQAAAA==.',
Ka='Kaevianda:BAAALgAECgUJCAAAAA==.Kageshootman:BAABLgAECn8XAAIPAAgJ0AzaCQBZAQAPAAgJ0AzaCQBZAQAAAA==.Kaleesh:BAACLgAFFH8IAAIkAAQJMSR0AQCAAQAkAAQJMSR0AQCAAQAuAAQKfyMAAiQACAmqJEcBAGgDACQACAmqJEcBAGgDAAAA.Kallux:BAABLgAECn8iAAIdAAgJ+xuuCAD6AQAdAAgJ+xuuCAD6AQAAAA==.Kananga:BAAALgAECgYJEwAAAA==.Karavira:BAAALgADCgcJDwAAAA==.Kasca:BAAALgADCgYJBgAAAA==.Kaybar:BAAALgADCgIJAgAAAA==.Kaylaeden:BAAALgADCggJCAAAAA==.',
Ke='Kelindina:BAAALgAECgMJCwAAAA==.Kelindinas:BAAALgAECgQJBwAAAA==.Kevinshart:BAAALgAECgUJBQAAAA==.',
Kh='Khalli:BAAALgAECgEJAQAAAA==.',
Ki='Kieleron:BAAALgAECgYJDgAAAA==.Kierlessa:BAAALgAECgYJCQABLgAFFAIJAgACAAAAAA==.Kiermac:BAAALgAECgUJDgAAAA==.Kiermaxim:BAABLgAECn8lAAIOAAgJNBwXGwA6AgAOAAgJNBwXGwA6AgABLgAFFAIJAgACAAAAAA==.Kierzenkai:BAAALgAFFAIJAgAAAA==.Kiragrande:BAABLgAECn8dAAIMAAkJwxDeFwCTAQAMAAkJwxDeFwCTAQAAAA==.Kiraneth:BAABLgAECn8gAAINAAgJMBB5FACLAQANAAgJMBB5FACLAQAAAA==.Kirbie:BAAALgADCgEJAQAAAA==.Kirial:BAAALgADCgcJBwAAAA==.Kiriku:BAAALgAECggJDQAAAA==.',
Kl='Klaysdnds:BAAALgADCggJEgAAAA==.',
Ko='Kobus:BAAALgADCgQJBAAAAA==.Korbinf:BAAALgAECgQJDAAAAA==.Kotok:BAAALgAECgQJBAAAAA==.',
Ku='Kungpownibs:BAAALgADCgUJBQAAAA==.Kurth:BAAALgADCgYJBgAAAA==.',
La='Lagartista:BAAALgAECgEJAQAAAA==.Larplord:BAAALgAECgYJDQAAAA==.',
Ld='Ldyelphaba:BAAALgAECgcJDwAAAA==.',
Li='Lilchungus:BAAALgADCgIJAwAAAA==.Lindórie:BAAALgAECgEJAQAAAA==.Liturgy:BAAALgADCgMJAwAAAA==.',
Lo='Logankord:BAABLgAECn8lAAIcAAgJKSMyBAC/AgAcAAgJKSMyBAC/AgAAAA==.Lokeira:BAABLgAECn8jAAILAAgJHhs7KQDqAQALAAgJHhs7KQDqAQAAAA==.Lolded:BAAALgADCgEJAQAAAA==.Lono:BAABLgAECn8iAAIFAAgJ1xFbQACFAQAFAAgJ1xFbQACFAQAAAA==.Loop:BAAALgADCgMJAwAAAA==.Lorcana:BAAALgAECgEJAQAAAA==.Lorstus:BAAALgADCgYJBgAAAA==.',
Lu='Lucory:BAAALgAECgEJAgABLgAECgUJFAAQAJIUAA==.Lumberjack:BAAALgADCgQJBgAAAA==.Luvbug:BAABLgAECn8WAAIHAAcJ3SJ9GAB2AgAHAAcJ3SJ9GAB2AgAAAA==.',
Ly='Lyara:BAACLgAFFH8PAAMLAAUJ4iNKAwDxAQALAAUJ4iNKAwDxAQAOAAIJ/Qc4GQCPAAAuAAQKfxkAAwsACAkVIFAJAOICAAsACAkVIFAJAOICAA4ABAkfFglbANgAAAAA.Lyi:BAAALgAECgUJBQAAAA==.Lythos:BAABLgAECn8ZAAIdAAgJjhNoGwBzAQAdAAgJjhNoGwBzAQAAAA==.Lyu:BAAALgAFFAEJAQABLgAFFAUJDwALAOIjAA==.Lyuu:BAABLgAFFH8GAAIQAAMJdxZNRAABAQAQAAMJdxZNRAABAQABLgAFFAUJDwALAOIjAA==.',
['Lø']='Lørdøfßud:BAABLgAECn8jAAMcAAgJxR+rCwAvAgAcAAgJ4RyrCwAvAgAhAAYJeCFCBwDnAQAAAA==.',
Ma='Macguffin:BAAALgADCgkJDgAAAA==.Machomans:BAAALgAECgEJAQABLgAECgcJFQAeAEAKAA==.Makimá:BAAALgADCgYJBgABLgAECggJGAAHANIVAA==.Malifae:BAABLgAECn8bAAITAAcJYSGVEwB3AgATAAcJYSGVEwB3AgAAAA==.Malimae:BAAALgADCgYJBgABLgAECgcJGwATAGEhAA==.Mankilla:BAAALgADCgUJBQAAAA==.Mansa:BAABLgAECn8iAAIlAAgJZBW6BADBAQAlAAgJZBW6BADBAQAAAA==.Mastamojo:BAABLgAECn8hAAIGAAkJnQUQJwBSAQAGAAkJnQUQJwBSAQAAAA==.Maulding:BAAALgADCgcJDgAAAA==.Maîev:BAAALgAECgMJAwAAAA==.',
Mc='Mcmurphy:BAAALgAECgUJDAAAAA==.Mctanky:BAAALgAECgEJAwAAAA==.',
Me='Mechadragon:BAAALgADCgYJDwAAAA==.Meepmeep:BAAALgAECgQJBQAAAA==.Meissen:BAAALgAECgYJEQAAAA==.Melendaren:BAAALgAECgEJAQAAAA==.Melestaria:BAAALgAECgEJAQAAAA==.Meltara:BAAALgADCgUJBQAAAA==.Menonk:BAAALgADCgQJBQAAAA==.Meowandi:BAAALgAECgIJAgAAAA==.Meowkug:BAAALgAECgEJAQAAAA==.Merscy:BAABLgAECn8bAAIRAAgJngpjIABFAQARAAgJngpjIABFAQAAAA==.Mertia:BAAALgAECgUJCwAAAA==.Messìah:BAAALgAECgcJDwAAAA==.Metamonster:BAABLgAECn8XAAMdAAYJiRClHgDMAAAdAAYJ4w+lHgDMAAAIAAYJ9QSwrgCCAAAAAA==.Meåny:BAAALgAECgYJCQAAAA==.',
Mi='Mikimiku:BAAALgAECgEJAQAAAA==.Miniav:BAAALgAECgIJAgAAAA==.Mirko:BAABLgAECn8VAAIeAAcJQArUXgDiAAAeAAcJQArUXgDiAAAAAA==.Mistiah:BAAALgAECgMJAwAAAA==.Mistyjoe:BAAALgADCgMJAwAAAA==.',
Ml='Mladjo:BAAALgAECgYJDAAAAA==.',
Mo='Mockery:BAABLgAECn8pAAISAAgJ9BNWAgDOAQASAAgJ9BNWAgDOAQAAAA==.Mokokniki:BAAALgADCggJCQAAAA==.Moneie:BAAALgAECgIJAgAAAA==.Monger:BAAALgADCgIJAgAAAA==.Monkyourself:BAAALgADCgYJCQAAAA==.Mooana:BAAALgAECgEJAQAAAA==.Moocowman:BAAALgAECgYJDgABLgAECggJCAACAAAAAA==.Moondo:BAAALgAECgcJBwAAAA==.Moone:BAAALgADCgYJBgAAAA==.Morticiá:BAAALgAECgYJCQAAAA==.Mortiferum:BAAALgADCgcJDQAAAA==.Mourningstar:BAACLgAFFH8MAAMIAAUJHiPgEgCHAQAIAAQJHiPgEgCHAQAdAAEJAACPLgAAAAAuAAQKfx8AAwgACQl5IDwUAAIDAAgACAkzIzwUAAIDAB0AAgm1EWMoAIcAAAEuAAUUBQkUAAgAsCEA.Mozaic:BAABLgAECn8pAAIiAAgJzhYnCQDjAQAiAAgJzhYnCQDjAQAAAA==.',
Mu='Mugrüíth:BAAALgAECgEJAQAAAA==.',
My='Myfeethurt:BAAALgADCgYJBgABLgAECggJIwAcAMUfAA==.Myragê:BAAALgADCgkJDQAAAA==.Myselia:BAAALgAECgcJEAAAAA==.Mystra:BAAALgAECgQJBQAAAA==.',
['Mè']='Mèany:BAAALgAECgUJBQABLgAECgYJCQACAAAAAA==.',
Na='Nad:BAAALgADCgQJBAAAAA==.Naek:BAAALgAECgEJAQAAAA==.Naekadin:BAAALgADCgEJAQABLgAECgEJAQACAAAAAA==.Natawista:BAAALgADCgcJEgAAAA==.Nazuren:BAAALgADCgEJAQAAAA==.',
Ne='Necromus:BAAALgAECgYJEAAAAA==.Nekra:BAAALgADCgEJAQAAAA==.',
Ni='Nibbi:BAAALgADCgEJAQAAAA==.Nic:BAAALgADCgEJAQAAAA==.Nichtaire:BAABLgAECn8XAAIeAAgJugmxRQAnAQAeAAgJugmxRQAnAQAAAA==.Niem:BAABLgAECn8VAAImAAcJSyVRAwDbAgAmAAcJSyVRAwDbAgAAAA==.Nilyaf:BAAALgADCgQJBAAAAA==.',
No='Nocturnum:BAABLgAECn8mAAIeAAgJZBUEIADIAQAeAAgJZBUEIADIAQAAAA==.Notkorbin:BAAALgAECgIJAgAAAA==.Notreeus:BAAALgAECgEJAQAAAA==.Nowotrius:BAAALgADCgUJBQAAAA==.',
Nu='Numb:BAAALgAECgYJEgAAAA==.',
Ny='Nyxstryl:BAACLgAFFH8HAAIgAAQJRQ9PAABcAQAgAAQJRQ9PAABcAQAuAAQKfxsAAiAACAktHi8BAPECACAACAktHi8BAPECAAAA.',
['Nô']='Nôkiaa:BAAALgAECgQJBgAAAA==.',
Ob='Obitus:BAAALgADCgEJAQABLgAECgYJCQACAAAAAA==.',
Od='Odahviing:BAAALgADCgQJBAAAAA==.Odin:BAAALgADCgYJBgAAAA==.Odium:BAAALgADCgMJAwABLgAFFAMJBwAHADYeAA==.',
Oh='Ohuln:BAAALgADCgcJCAABLgAFFAYJFgAHACciAA==.',
Ol='Oldmage:BAAALgADCgUJBQAAAA==.Oldmongerpal:BAAALgAECgEJAQAAAA==.',
On='Onetwocowpow:BAABLgAECn8sAAIMAAkJlBXnCwAsAgAMAAkJlBXnCwAsAgAAAA==.',
Oo='Ooshiny:BAAALgAECgEJAQAAAA==.',
Or='Orclard:BAAALgAECgIJAgAAAA==.Ordanith:BAABLgAECn8uAAIFAAkJeSFGCQDBAgAFAAkJeSFGCQDBAgAAAA==.Orionn:BAACLgAFFH8QAAIHAAQJmB9RBwCCAQAHAAQJmB9RBwCCAQAuAAQKfzAAAgcACQnSI3wCACEDAAcACQnSI3wCACEDAAAA.Ornan:BAAALgAECgQJBAAAAA==.Ororo:BAAALgAECgIJAgAAAA==.',
Os='Osø:BAAALgAECgYJEAAAAA==.',
Ov='Oven:BAABLgAECn8gAAINAAgJVxakDQDeAQANAAgJVxakDQDeAQAAAA==.',
Pa='Pastaa:BAAALgAECgcJEwAAAA==.',
Ph='Phil:BAAALgAECgcJEwAAAA==.Phillio:BAAALgAECgQJBAAAAA==.Phoenixy:BAAALgADCgQJBAAAAA==.Phosphate:BAAALgAECgYJCQAAAA==.',
Pi='Pippins:BAAALgAECgEJAQAAAA==.',
Pl='Plunto:BAAALgADCgUJBQAAAA==.',
Po='Po:BAAALgAECgYJCQAAAA==.Portucala:BAAALgADCgYJCQAAAA==.',
Pr='Prarg:BAAALgADCgcJBwAAAA==.Praystation:BAAALgAECgUJCAAAAA==.',
Py='Pyral:BAAALgAECgYJDAAAAA==.',
Qu='Quarm:BAAALgADCgUJBQAAAA==.',
Ra='Raekeshh:BAAALgAECgkJEAAAAA==.Raelone:BAABLgAECn8XAAMKAAcJow8aYwAJAQAKAAUJYQ0aYwAJAQAVAAUJOhGoOwDFAAAAAA==.Rageofmommy:BAAALgADCgMJAwAAAA==.Raidoe:BAABLgAECn8qAAMMAAgJgByTCQBVAgAMAAgJgByTCQBVAgANAAIJ+QruYAAxAAAAAA==.Raknaruk:BAAALgAECgEJAQAAAA==.Rakwiz:BAAALgADCgEJAQAAAA==.Rangérz:BAABLgAECn8iAAIHAAgJbBj9GwD1AQAHAAgJbBj9GwD1AQAAAA==.Rant:BAAALgAECgQJCAAAAA==.Rasa:BAAALgAECgUJCAAAAA==.Ratio:BAAALgADCgYJBgAAAA==.',
Re='Redshammy:BAAALgAECgYJEAAAAA==.Redward:BAABLgAECn8fAAIFAAgJagoITQBeAQAFAAgJagoITQBeAQAAAA==.',
Rh='Rhell:BAACLgAFFH8MAAIGAAMJshnAFwDmAAAGAAMJshnAFwDmAAAuAAQKfyoAAgYACQn5Hr4NAKoCAAYACQn5Hr4NAKoCAAAA.',
Ri='Rinche:BAABLgAECn8rAAMOAAkJQBACEwDBAQAOAAkJQBACEwDBAQALAAgJ6gliPQAPAQAAAA==.Rintche:BAAALgAECgMJAwAAAA==.',
Ro='Rolland:BAABLgAECn8UAAIPAAYJDSB6BQDNAQAPAAYJDSB6BQDNAQAAAA==.Rollf:BAAALgADCgUJBQAAAA==.Rootbeamxo:BAAALgADCgUJBgAAAA==.Rosefyre:BAAALgAECggJEQAAAA==.',
Ru='Rudo:BAABLgAECn8YAAIHAAgJ0hVZIgA3AgAHAAgJ0hVZIgA3AgAAAA==.Rumproblem:BAAALgAECgYJCgAAAA==.Runnamuuk:BAABLgAECn8jAAIeAAgJiQ7JMgBqAQAeAAgJiQ7JMgBqAQAAAA==.Rush:BAAALgAECgEJAQAAAA==.',
Ry='Ryeger:BAABLgAECn8hAAMjAAgJuxRZBgDhAQAjAAgJuxRZBgDhAQATAAMJyATDQwBuAAAAAA==.',
['Rä']='Räsa:BAAALgAECgEJAQAAAA==.',
['Ró']='Róótbear:BAABLgAECn8gAAImAAgJkhLvDQAqAQAmAAgJkhLvDQAqAQAAAA==.',
Sa='Sadrobot:BAAALgAECgEJBAABLgAECgMJCwACAAAAAA==.Sahbe:BAAALgADCgYJBgAAAA==.Salfros:BAAALgADCgkJCwAAAA==.Sallydapally:BAAALgADCgYJBwAAAA==.Samovar:BAABLgAECn8jAAIFAAgJvAx4RgByAQAFAAgJvAx4RgByAQAAAA==.Sandbones:BAAALgAECgMJAwABLgAECggJKQASAPQTAA==.Sandraice:BAABLgAECn8fAAIFAAgJ0QYyhwBsAQAFAAgJ0QYyhwBsAQAAAA==.Sandwiches:BAAALgAECgYJEgAAAA==.Sanguinne:BAAALgAECgIJAgAAAA==.Sansami:BAABLgAECn8iAAIUAAYJHByfJQDXAQAUAAYJHByfJQDXAQAAAA==.Sarraloesh:BAAALgADCgIJAgAAAA==.Satoshi:BAAALgAECgUJBQAAAA==.',
Sc='Scalebagz:BAAALgAECggJEgAAAA==.Schism:BAAALgADCgkJDgAAAA==.',
Se='Selûne:BAAALgAECgMJBQAAAA==.Sentren:BAAALgADCgcJDAAAAA==.Senyorseven:BAAALgAECgUJDQAAAA==.Seo:BAAALgADCgUJBQAAAA==.Setresh:BAABLgAECn8uAAIWAAkJgxVvBgBKAgAWAAkJgxVvBgBKAgAAAA==.Severus:BAAALgADCgMJAwAAAA==.',
Sh='Shadöwsöng:BAABLgAECn8gAAIiAAcJxQrdFgAMAQAiAAcJxQrdFgAMAQAAAA==.Shaedelana:BAAALgAECgUJDAAAAA==.Shamrox:BAAALgAECgYJBwAAAA==.Shamwowhex:BAAALgAECggJCgAAAA==.Shangöh:BAAALgAECgYJBgABLgAECgkJJwADAGoeAA==.Shinygoat:BAAALgADCgIJAgABLgAECggJKAAJAAAiAA==.Shivyn:BAABLgAECn8kAAMLAAcJTw1MMwA/AQALAAcJTw1MMwA/AQAOAAEJFwWzjQAqAAAAAA==.Shoeman:BAAALgAECgEJAQAAAA==.Shokyo:BAAALgADCgUJBQAAAA==.Shoota:BAAALgAECgEJAQABLgAFFAYJFgAHACciAA==.Shootybooty:BAAALgAECgYJBgABLgAECgYJEgACAAAAAA==.Shugarion:BAAALgADCgUJAQAAAA==.Shàken:BAAALgADCgYJCgAAAA==.',
Si='Sibadeekay:BAABLgAECn8rAAMIAAkJgRh6GwAlAgAIAAkJgRh6GwAlAgAdAAUJrQ9QLgDMAAAAAA==.Sickkid:BAABLgAECn8hAAIcAAYJlho5GQCdAQAcAAYJlho5GQCdAQAAAA==.Siegekaiser:BAAALgADCgcJEwAAAA==.Silvershine:BAAALgAECgYJDwAAAA==.Silverwolf:BAAALgADCgcJBwAAAA==.Sindrya:BAAALgAECgMJBQAAAA==.',
Sk='Skoobastank:BAAALgADCgIJAgAAAA==.Skunkt:BAAALgADCgYJCAAAAA==.',
Sl='Slimeto:BAAALgAECgMJBQAAAA==.',
Sm='Smaeg:BAAALgAECgMJAwABLgAECgkJAgACAAAAAA==.Smeef:BAAALgAECgQJBAAAAA==.Smoothvelvet:BAAALgAECgkJDAAAAA==.',
Sn='Snays:BAAALgAECgYJEAAAAA==.Sneeger:BAAALgAECgIJAgAAAA==.Snuggles:BAABLgAECn8UAAIfAAYJkxkPEACCAQAfAAYJkxkPEACCAQABLgAFFAQJCQAWACEQAA==.',
So='Solidgen:BAAALgAECgEJAQAAAA==.Solobolo:BAAALgAECgQJBAABLgAECgQJBAACAAAAAA==.Sosreaper:BAAALgADCgYJCgAAAA==.',
Sp='Spadez:BAAALgAECggJEQAAAA==.Splortus:BAAALgAECgEJAQAAAA==.Sprath:BAAALgAECgEJAQAAAA==.Sprinkle:BAAALgAECgMJCAAAAA==.',
Ss='Ssraeshza:BAAALgAECgYJDQABLgAFFAUJFAAEAKYhAA==.',
St='Staretra:BAABLgAECn8lAAMXAAkJzwxWEgC1AQAXAAkJzwxWEgC1AQARAAMJjQOrPQBxAAAAAA==.Stficyhot:BAAALgADCgMJBgAAAA==.',
Su='Subsub:BAAALgADCgEJAQAAAA==.Sungjinwoo:BAAALgAECgYJDgAAAA==.Sunslap:BAAALgAECgYJEAAAAA==.Susanaa:BAAALgAECgUJBwAAAA==.',
Sy='Symana:BAABLgAECn8mAAIRAAgJ8htbFAA7AgARAAgJ8htbFAA7AgAAAA==.Syradra:BAAALgAECgIJAgAAAA==.Sytka:BAAALgAECgcJBwAAAA==.',
['Sè']='Sèan:BAAALgADCgcJDAAAAA==.',
['Sì']='Sìlvertìger:BAAALgAECgYJCQAAAA==.',
Ta='Taadra:BAABLgAECn8pAAILAAgJxBv3DABkAgALAAgJxBv3DABkAgAAAA==.Talfuki:BAAALgADCgUJBQAAAA==.Taliliia:BAAALgAECgEJAQAAAA==.Talkova:BAAALgAECgYJDgAAAA==.Talohae:BAAALgAFFAMJAwAAAA==.Talona:BAAALgAECgQJBAABLgAFFAQJBwAgAEUPAA==.Tandaan:BAAALgADCgkJCQABLgAECgkJEAACAAAAAA==.Tanjent:BAAALgAECgUJDAAAAA==.Tapio:BAABLgAECn8VAAIWAAYJZxVyFgBcAQAWAAYJZxVyFgBcAQAAAA==.Tatsuma:BAAALgAECgQJBAABLgAECgcJFgAFALcWAA==.Tatsumå:BAAALgAECgYJDwABLgAECgcJFgAFALcWAA==.',
Te='Terp:BAAALgAECgMJBgAAAA==.',
Th='Thalfinore:BAAALgAECgcJDgAAAA==.Thalrissa:BAAALgAECgMJAwAAAA==.Thorincan:BAAALgAECgkJBwAAAA==.Thort:BAAALgAECgMJAwAAAA==.Thuglifé:BAAALgADCgYJDQAAAA==.',
Ti='Tia:BAAALgAECgEJAQABLgAECgQJBQACAAAAAA==.Tidemaiden:BAAALgAECgYJEAAAAA==.Tiktac:BAAALgADCgUJCAAAAA==.Tim:BAAALgAECgEJAgAAAA==.Tinynflaccid:BAAALgADCgMJAwAAAA==.Tipsymancer:BAABLgAECn8sAAIUAAkJ0RukBAChAgAUAAkJ0RukBAChAgAAAA==.Tirael:BAAALgAECgYJBQAAAA==.',
To='Tomö:BAAALgAECgIJAgAAAA==.Touji:BAAALgADCgcJDAAAAA==.',
Tr='Treesus:BAABLgAECn8eAAITAAkJlRmRGwAmAgATAAkJlRmRGwAmAgAAAA==.Trinket:BAAALgADCgEJAQABLgAECggJGAAHANIVAA==.Trollroom:BAAALgADCgkJCQAAAA==.Truemagi:BAAALgAECgIJAQAAAA==.Tryiall:BAAALgAECgcJBwAAAA==.',
Tw='Twinklehoofs:BAAALgAECgUJBgAAAA==.Twiztid:BAAALgADCgYJCAAAAA==.',
Ty='Tyrethal:BAAALgADCgcJBwAAAA==.',
['Tñ']='Tñer:BAABLgAECn8aAAQQAAgJ4iNWEwB+AgAQAAgJWyFWEwB+AgASAAMJBCS7BAA9AQAnAAEJTQ0WDwA8AAAAAA==.',
Ul='Ulahwekeheia:BAABLgAECn8gAAIDAAgJuRmsHADeAQADAAgJuRmsHADeAQAAAA==.',
Ur='Uruloki:BAABLgAFFH8FAAIaAAMJfgZdJQDNAAAaAAMJfgZdJQDNAAAAAA==.',
Us='Usidore:BAAALgADCgcJBwAAAA==.',
Va='Vainin:BAAALgAECgQJBgAAAA==.Valle:BAAALgAECgYJCgAAAA==.Valry:BAAALgADCgIJBAAAAA==.Vanilla:BAAALgAECgEJAQABLgAFFAMJCwAUACQKAA==.Variable:BAAALgADCgEJAQAAAA==.Vashdin:BAABLgAECn8VAAIFAAYJIBpnRwBvAQAFAAYJIBpnRwBvAQAAAA==.',
Ve='Vectorvega:BAAALgAECgEJAQABLgAECggJGAAHANIVAA==.Veicilia:BAAALgAECgMJAwAAAA==.Velashis:BAABLgAECn8VAAIDAAgJNhf5LwDsAQADAAgJNhf5LwDsAQAAAA==.Velshariel:BAAALgADCgUJBQAAAA==.Vermin:BAAALgAECggJCAAAAA==.',
Vi='Viable:BAAALgAECgQJBgAAAA==.Vibes:BAAALgADCgkJEQAAAA==.Victorvega:BAAALgAECgMJAwABLgAECggJGAAHANIVAA==.Vilt:BAAALgADCgMJAwAAAA==.Visandar:BAAALgAECgkJDQAAAA==.Vivif:BAACLgAFFH8KAAMNAAMJuxsFFQCsAAANAAIJlxkFFQCsAAAMAAMJXA2+HQCGAAAuAAQKfxYAAw0ACQmQHREQAH8CAA0ACAlXHREQAH8CAAwABQnvHzQnABEBAAAA.Vivillian:BAAALgAECgkJDAAAAA==.Vixsin:BAAALgADCgkJEAAAAA==.',
Vo='Vodmos:BAAALgAECgEJAQAAAA==.Vordilina:BAAALgAECggJEwAAAA==.',
Vr='Vresim:BAABLgAECn8XAAQZAAgJKhnxEwAGAgAZAAgJKhnxEwAGAgAbAAQJxRgXDADTAAAaAAEJygOxYAApAAAAAA==.',
Vu='Vuginhood:BAAALgADCgEJAgAAAA==.Vugnus:BAABLgAECn8VAAMLAAYJjho3MwBAAQALAAUJ6Rk3MwBAAQAOAAQJGgwiPAC7AAAAAA==.',
['Vé']='Véxx:BAABLgAECn8cAAQJAAYJmB4zBgCeAQAJAAYJmB4zBgCeAQAfAAUJYAiwQgDtAAAeAAEJdAGW9QAZAAAAAA==.',
Wa='Wannan:BAAALgADCgYJCQAAAA==.Wardamon:BAAALgADCgYJBgABLgAECgEJAQACAAAAAA==.Warihor:BAABLgAECn8oAAMhAAgJHgyBEgAsAQAcAAgJrwlFHgB3AQAhAAgJGAmBEgAsAQAAAA==.',
We='Weezle:BAAALgAECgMJBgAAAA==.Westrin:BAABLgAECn8jAAIgAAkJRSHOAACaAgAgAAkJRSHOAACaAgAAAA==.',
Wi='Wife:BAAALgAECgIJAgAAAA==.Wiz:BAAALgADCgcJDAAAAA==.',
Wo='Worgendork:BAAALgAECgkJBgAAAA==.',
Wr='Wrangler:BAAALgAECgcJBAAAAA==.',
Wy='Wyndeline:BAAALgAECgUJCAAAAA==.',
Xa='Xarrie:BAAALgADCgMJCQAAAA==.',
Xc='Xc:BAAALgADCgcJBwABLgAECgQJBQACAAAAAA==.',
Xo='Xorxel:BAAALgAECgMJBAAAAA==.',
Ya='Yacob:BAABLgAECn8cAAIRAAgJYRzsCABeAgARAAgJYRzsCABeAgAAAA==.',
Yg='Yggrasdil:BAABLgAECn8nAAIDAAkJah6aBQD9AgADAAkJah6aBQD9AgAAAA==.',
Yh='Yhwach:BAABLgAFFH8HAAIdAAMJKgrhFACvAAAdAAMJKgrhFACvAAAAAA==.',
Yi='Yikes:BAAALgADCgEJAQAAAA==.',
Ym='Ymir:BAAALgAECgcJDQABLgAECgMJBAACAAAAAA==.',
Yo='Yolasses:BAAALgAECgYJEAAAAA==.',
Yu='Yuie:BAAALgAECgQJBQAAAA==.Yukitaiga:BAAALgAECgQJCAABLgABCgMJAwACAAAAAA==.Yule:BAAALgAECgQJBAAAAA==.',
Za='Zaeden:BAABLgAECn8bAAIMAAYJxB6ZFgANAgAMAAYJxB6ZFgANAgAAAA==.Zaftdh:BAABLgAECn8aAAIeAAkJHhFeJQCpAQAeAAkJHhFeJQCpAQAAAA==.Zaha:BAABLgAECn8eAAIQAAYJ2iKYXAAkAgAQAAYJ2iKYXAAkAgAAAA==.Zaidane:BAAALgADCgYJBgAAAA==.Zarov:BAAALgADCgQJBAAAAA==.Zarthan:BAAALgAECgEJAQAAAA==.',
Zd='Zdps:BAAALgAECgQJAgAAAA==.',
Ze='Zem:BAABLgAECn8hAAIcAAgJMh/cBgCAAgAcAAgJMh/cBgCAAgAAAA==.Zeroultra:BAABLgAECn8eAAIcAAYJKhw6FwCtAQAcAAYJKhw6FwCtAQAAAA==.Zeusmos:BAABLgAECn8jAAINAAgJmCUyAgD5AgANAAgJmCUyAgD5AgAAAA==.',
Zi='Zithenex:BAABLgAECn8VAAIbAAYJOBCOCAAkAQAbAAYJOBCOCAAkAQAAAA==.',
Zw='Zwar:BAAALgAECgEJAQAAAA==.',
Zy='Zynsis:BAAALgADCgYJCQAAAA==.',
['Ál']='Álister:BAAALgAECgMJBAAAAA==.',
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
