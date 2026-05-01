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

local lookup = {'Mage-Frost','DeathKnight-Unholy','Druid-Restoration','DeathKnight-Frost','Hunter-BeastMastery','Hunter-Marksmanship','Evoker-Preservation','Paladin-Retribution','Druid-Feral','Hunter-Survival','Priest-Shadow','DemonHunter-Devourer','Rogue-Subtlety','Rogue-Assassination','Unknown-Unknown','Mage-Fire','Evoker-Augmentation','Evoker-Devastation','Paladin-Protection','Warlock-Affliction','Warlock-Demonology','Warrior-Protection','DemonHunter-Vengeance','DeathKnight-Blood','Monk-Brewmaster','Druid-Balance','Mage-Arcane','Warlock-Destruction','Paladin-Holy','Priest-Discipline','Priest-Holy','Warrior-Fury','Shaman-Restoration','DemonHunter-Havoc','Shaman-Elemental','Monk-Mistweaver','Shaman-Enhancement','Monk-Windwalker','Warrior-Arms','Druid-Guardian',}
local provider = {region='US',realm='Firetree',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abacabb:BAAALgAECgQJBQAAAA==.',
Ac='Acanthiex:BAAALgADCgQJBAAAAA==.',
Ad='Adnarimn:BAAALgAECgEJAQAAAA==.Adondias:BAABLgAECn8hAAIBAAgJ3SLaCQChAgABAAgJ3SLaCQChAgAAAA==.',
Ae='Aelanthus:BAAALgADCgEJAQAAAA==.Aelinn:BAAALgADCgEJAQAAAA==.',
Ag='Agrevail:BAAALgAECgYJDQAAAA==.',
Ai='Aidendk:BAABLgAECn8aAAICAAgJlx/RJACqAgACAAgJlx/RJACqAgAAAA==.',
Ak='Akrib:BAAALgADCgUJBQAAAA==.Akryllic:BAABLgAECn8eAAIDAAcJ/hw6DgApAgADAAcJ/hw6DgApAgAAAA==.',
Al='Aldari:BAACLgAFFH8NAAIBAAUJfRn9FwBlAQABAAUJfRn9FwBlAQAuAAQKfxwAAgEACQndJPAHAIoDAAEACQndJPAHAIoDAAAA.Allen:BAAALgADCgcJBwAAAA==.Allydk:BAABLgAECn8nAAMCAAkJjiNbGQDkAgACAAkJjiNbGQDkAgAEAAQJeBw/BwADAQAAAA==.Altrag:BAABLgAECn8pAAMFAAkJsRwVBQCpAgAFAAkJsRwVBQCpAgAGAAEJmAHemQAaAAAAAA==.Aluc:BAABLgAECn8iAAIHAAgJSQ9jCgBxAQAHAAgJSQ9jCgBxAQAAAA==.Alyrssa:BAAALgAECgYJBgAAAA==.',
An='Andilar:BAABLgAECn8ZAAIIAAgJ/Rg7RgARAgAIAAgJ/Rg7RgARAgAAAA==.Andrepov:BAAALgAECgEJBQAAAA==.Anehii:BAABLgAECn8lAAIJAAgJWgpWCQBUAQAJAAgJWgpWCQBUAQAAAA==.Aniia:BAAALgAECgYJDgAAAA==.Animaldude:BAABLgAECn8tAAMKAAkJXB8qBQC8AgAKAAkJXB8qBQC8AgAGAAEJ3gRakAAqAAAAAA==.Anjera:BAABLgAECn8UAAILAAYJ+hSAGwAhAQALAAYJ+hSAGwAhAQAAAA==.Anotherdrood:BAAALgAECgYJBgAAAA==.Anslayer:BAAALgAECgEJAQAAAA==.Anémie:BAAALgADCgkJDwAAAA==.',
Ap='Apexis:BAABLgAECn8UAAIMAAYJ9wsHhwAYAQAMAAYJ9wsHhwAYAQAAAA==.Apolion:BAAALgAECgMJBAAAAA==.',
Ar='Arctodus:BAAALgAECgYJCgAAAA==.Arghuul:BAABLgAECn8pAAMNAAkJEh1yBwAZAwANAAkJEh1yBwAZAwAOAAEJ4RujGgBTAAAAAA==.Arks:BAABLgAECn8YAAIDAAgJiBPEHwCCAQADAAgJiBPEHwCCAQAAAA==.Arksmash:BAAALgADCgcJBwAAAA==.',
As='Asperges:BAAALgAECggJEwAAAA==.Astropâ:BAAALgAECgEJAQAAAA==.',
Ax='Axsisdknight:BAAALgAECgEJAQAAAA==.',
Az='Azasei:BAAALgADCgMJBAAAAA==.Azathoth:BAAALgADCgUJBwABLgADCgcJDAAPAAAAAA==.',
['Aë']='Aëlana:BAABLgAECn8kAAIBAAgJdRpsJwDIAQABAAgJdRpsJwDIAQAAAA==.',
Ba='Baconn:BAACLgAFFH8LAAIIAAQJsxuWCQBhAQAIAAQJsxuWCQBhAQAuAAQKfx4AAggABwnuJCIfALECAAgABwnuJCIfALECAAAA.Bailey:BAAALgADCgQJBAAAAA==.Baileyc:BAAALgAECgQJBAAAAA==.Balkhan:BAAALgADCgMJAwAAAA==.Balun:BAAALgAECgEJAwAAAA==.Banza:BAAALgAECgIJAgAAAA==.Barsh:BAABLgAECn8YAAIMAAYJThkHMgAbAQAMAAYJThkHMgAbAQABLgAECgkJJwAQAAofAA==.Battlebidet:BAAALgAECgEJAQAAAA==.',
Be='Beauregarde:BAAALgADCggJBgAAAA==.Beef:BAACLgAFFH8OAAIRAAUJtxxqCgBaAQARAAUJtxxqCgBaAQAuAAQKfxoAAxEACAkHJvQFACQDABEACAl4I/QFACQDABIABAlBJRIUAKUBAAAA.Beefdido:BAABLgAECn8cAAIOAAgJ9RQeAwDPAQAOAAgJ9RQeAwDPAQAAAA==.Beefstew:BAAALgAECgMJAwAAAA==.Befouled:BAAALgAECgcJEQAAAA==.Belinos:BAAALgADCgEJAQAAAA==.Belithe:BAABLgAECn8UAAITAAYJ8AU2GwCHAAATAAYJ8AU2GwCHAAAAAA==.Benson:BAAALgADCgIJAgAAAA==.Berrymanalow:BAACLgAFFH8GAAIBAAMJdwYTPQDYAAABAAMJdwYTPQDYAAAuAAQKfyAAAgEACAlWEnpkAA8CAAEACAlWEnpkAA8CAAAA.',
Bi='Bigpapapumpz:BAAALgAECgYJBwAAAA==.Bijtoo:BAABLgAECn8hAAMUAAgJaxqSAQD3AQAUAAgJaxqSAQD3AQAVAAUJXQ0lVgDvAAAAAA==.Bikkels:BAAALgADCgQJBgABLgAECgUJBQAPAAAAAA==.Bingsoo:BAABLgAECn8nAAIBAAkJLhhCEQBSAgABAAkJLhhCEQBSAgAAAA==.Bist:BAAALgAECgUJBwABLgAECgcJHwAIAI0lAA==.Bistopher:BAABLgAECn8fAAIIAAcJjSUGFADzAgAIAAcJjSUGFADzAgAAAA==.Bisty:BAAALgADCgYJCgABLgAECgcJHwAIAI0lAA==.',
Bj='Bjorney:BAABLgAECn8VAAILAAgJIgpDEgB0AQALAAgJIgpDEgB0AQAAAA==.',
Bl='Blankspace:BAAALgAECgUJCgAAAA==.Blaserr:BAABLgAECn8WAAIWAAgJvBbMFQCxAQAWAAgJvBbMFQCxAQAAAA==.Blessurface:BAAALgAECgIJAgAAAA==.Blindfire:BAABLgAECn8hAAIBAAkJ8x1iHAAFAwABAAkJ8x1iHAAFAwAAAA==.Blindspirit:BAAALgAECgYJDQAAAA==.Blindvngence:BAABLgAECn8bAAIXAAgJ1BSfCADuAQAXAAgJ1BSfCADuAQAAAA==.Blizzerker:BAAALgAECgEJAQAAAA==.Bloodrayne:BAAALgADCgUJDAAAAA==.Bludoosh:BAAALgAECgYJDQAAAA==.Blumken:BAAALgADCgEJAQAAAA==.',
Bo='Bombpops:BAAALgADCgEJAQABLgAECgEJAQAPAAAAAA==.Bonkdeath:BAABLgAECn8WAAMCAAcJKAkgZwDVAAACAAYJDgogZwDVAAAYAAEJqgRcLgAiAAAAAA==.Boomskii:BAAALgADCgIJAgAAAA==.Boomymonk:BAABLgAECn8YAAIZAAcJsR8xFABuAgAZAAcJsR8xFABuAgAAAA==.Boss:BAAALgAFFAQJBAABLgAFFAYJEgAaAAMcAA==.Bourius:BAAALgAECgUJBgABLgAFFAQJBgAIACgIAA==.Bowzette:BAAALgAECgQJBAAAAA==.',
Br='Br:BAABLgAECn8bAAIDAAkJUiBcBQA3AwADAAkJUiBcBQA3AwAAAA==.Brauxx:BAAALgADCgcJCQAAAA==.Breadermonk:BAAALgAECgYJEQAAAA==.Brezanyou:BAABLgAECn8XAAIDAAYJTgqycgD+AAADAAYJTgqycgD+AAAAAA==.Broly:BAAALgADCgcJDAAAAA==.Brotherblud:BAAALgADCgkJCgAAAA==.Brøx:BAABLgAECn8iAAICAAgJgR3aCwBrAgACAAgJgR3aCwBrAgAAAA==.',
Bu='Bubbelhearth:BAAALgAECgYJDAAAAA==.Budyzer:BAAALgADCgYJBwAAAA==.Builtdif:BAAALgADCgYJBgABLgAECggJLAAIADYkAA==.Bumbaclottx:BAAALgAECgMJBAAAAA==.Bunnyboy:BAAALgAECgQJCQAAAA==.Burlen:BAABLgAECn8aAAMBAAgJuRvSRwBgAgABAAgJuRvSRwBgAgAbAAQJxBpoDQDyAAAAAA==.Bustarime:BAAALgADCgkJJQAAAA==.Buyagram:BAAALgADCgIJAQAAAA==.',
Bw='Bwonsamdeez:BAAALgADCgYJBgAAAA==.',
['Bî']='Bîrth:BAABLgAECn8kAAIBAAkJAiCvFAA1AgABAAkJAiCvFAA1AgAAAA==.',
Ca='Caeleste:BAAALgAECgYJCwAAAA==.Calic:BAABLgAECn8kAAMcAAgJzhxoBgBpAgAcAAgJzhxoBgBpAgAVAAQJdRHsXwDTAAAAAA==.Calryuu:BAABLgAECn8YAAIZAAcJvB5xCgDkAQAZAAcJvB5xCgDkAQAAAA==.Caltrask:BAAALgAECgIJAgAAAA==.Cambiön:BAABLgAECn8kAAIBAAgJeBoKFgAsAgABAAgJeBoKFgAsAgAAAA==.Cameltoetem:BAAALgAECgQJAwAAAA==.Canape:BAABLgAECn8XAAIdAAYJHBvEJgATAQAdAAYJHBvEJgATAQAAAA==.Capnmurlock:BAAALgADCgEJAQAAAA==.Captnmurzzp:BAAALgADCgkJDgAAAA==.Carpetcrumbs:BAAALgAECgEJAQAAAA==.Castasaurus:BAAALgAECgQJBAAAAA==.Catharsis:BAACLgAFFH8TAAMeAAYJjiLTAgDhAQAeAAYJOCLTAgDhAQAfAAEJHCUlEQBiAAAuAAQKfyAAAx4ACQn5JSEAAOkDAB4ACQn5JSEAAOkDAB8ABwlYJQkKAKwCAAAA.',
Ce='Ceer:BAAALgADCggJDQAAAA==.Cenno:BAABLgAECn8kAAICAAgJthbkHgDOAQACAAgJthbkHgDOAQAAAA==.Cerioth:BAAALgAECgQJBAAAAA==.',
Ch='Chantyu:BAAALgADCgUJCAABLgAECgYJFwADAE4KAA==.Charlixcx:BAAALgADCgEJAQAAAA==.Chickenman:BAAALgAECgcJDgAAAA==.Chickienuggs:BAAALgADCgcJCgAAAA==.Chiflado:BAAALgAECgcJCwAAAA==.Chillinda:BAAALgAECgIJBQAAAA==.Chillpoppin:BAAALgAECgYJEQAAAA==.Chinpokomon:BAAALgAECgkJMQAAAQ==.Chompsy:BAABLgAECn8dAAIBAAgJrxm9QQBzAgABAAgJrxm9QQBzAgAAAA==.Chubbychi:BAAALgAECgEJAQABLgAECgYJFwADAE4KAA==.',
Ci='Ciei:BAAALgADCgIJAgAAAA==.Cilya:BAAALgAECgYJCAAAAA==.Citrusghoul:BAAALgAECgYJDQAAAA==.Citruslite:BAAALgAECgEJAQAAAA==.',
Cl='Clockworkx:BAAALgAECgEJAQAAAA==.',
Co='Cole:BAABLgAECn8iAAMWAAcJ+h9yCACvAQAWAAcJZBdyCACvAQAgAAYJ9iBzEwCaAQAAAA==.Conceptheals:BAAALgAECgYJDAAAAA==.Confessia:BAAALgAECgYJCgAAAA==.Constantine:BAAALgAECgEJAQAAAA==.Costcobeef:BAAALgAECgEJAQABLgAECgIJAgAPAAAAAA==.Couchlocked:BAAALgADCgEJAQAAAA==.',
Cr='Crackle:BAAALgAECgMJAwAAAA==.Criticalmiss:BAAALgAECgQJBwABLgAFFAUJEgACAJQdAA==.Critsae:BAACLgAFFH8JAAICAAQJHRmJDwBjAQACAAQJHRmJDwBjAQAuAAQKfx8AAgIACAk2IFoWAPYCAAIACAk2IFoWAPYCAAAA.Critydarkirn:BAABLgAECn8oAAQdAAkJFx7lHAAvAgAdAAkJFx7lHAAvAgAIAAUJnBFrUQAZAQATAAUJ+BWqDgAWAQAAAA==.Crypticdh:BAABLgAECn8OAAIMAAYJhBWxYQB8AQAMAAYJhBWxYQB8AQAAAA==.Cryptø:BAAALgAECgYJBwAAAA==.',
Cv='Cvrcvss:BAABLgAECn8ZAAQVAAgJGhNPYQCmAQAVAAcJlRNPYQCmAQAcAAUJhg4YKQAeAQAUAAEJAABtLgBBAAAAAA==.',
Cy='Cybele:BAABLgAECn8eAAIMAAgJ/x7uDAATAgAMAAgJ/x7uDAATAgAAAA==.Cypriss:BAAALgAECgEJAgAAAA==.',
['Cë']='Cëlestial:BAAALgAECgYJBwAAAA==.',
Da='Dabadjuju:BAAALgAECgQJCAAAAA==.Dagoonfather:BAAALgAECggJEwAAAA==.Dale:BAAALgADCgMJAwAAAA==.Dandorllan:BAACLgAFFH8LAAIdAAMJ8x7jEADyAAAdAAMJ8x7jEADyAAAuAAQKfycAAx0ACQkHI0ABAHgDAB0ACQkHI0ABAHgDAAgACQkyJYkAAG4DAAAA.Dandowaz:BAABLgAFFH8HAAIhAAMJLhbmFgDTAAAhAAMJLhbmFgDTAAABLgAFFAMJCwAdAPMeAA==.Dandyrandy:BAABLgAECn8hAAMIAAkJuQ+DWADZAQAIAAkJuQ+DWADZAQAdAAgJJRGqLgDJAQAAAA==.Dani:BAAALgADCgUJCQAAAA==.Dareick:BAAALgAECgQJDAAAAA==.Darthashmire:BAAALgAECgQJBQAAAA==.Darthavenger:BAAALgAECgYJDAAAAA==.Dayday:BAABLgAECn8bAAIaAAgJ0hA6EwBuAQAaAAgJ0hA6EwBuAQAAAA==.Dazzazn:BAAALgAECgYJDwAAAA==.',
De='Decious:BAABLgAECn8hAAIIAAgJlhtkEQAwAgAIAAgJlhtkEQAwAgAAAA==.Deepfist:BAABLgAECn8jAAIZAAgJwR0WBgA/AgAZAAgJwR0WBgA/AgAAAA==.Deepfried:BAAALgAECgMJBAAAAA==.Defjam:BAABLgAECn8eAAIBAAcJBxxEVgA2AgABAAcJBxxEVgA2AgAAAA==.Delath:BAAALgAECgIJAgAAAA==.Delicia:BAABLgAECn8YAAMeAAcJuA/fEACAAQAeAAcJWgzfEACAAQAfAAYJQA86PgBBAQAAAA==.Dellbelphine:BAABLgAECn8nAAIIAAgJLR4QEAA9AgAIAAgJLR4QEAA9AgAAAA==.Deminis:BAAALgADCgYJBgAAAA==.Demonbud:BAAALgAECgYJCQABLgAECggJGwASAAAgAA==.Demoncarlos:BAACLgAFFH8LAAIMAAQJJxqHCgBhAQAMAAQJJxqHCgBhAQAuAAQKfyAAAgwACAkBHgceAJ4CAAwACAkBHgceAJ4CAAAA.Demonicscale:BAACLgAFFH8HAAIVAAMJHgIOOwC4AAAVAAMJHgIOOwC4AAAuAAQKfyUAAxUACAlyEkBPANoBABUACAlyEkBPANoBABQAAQlIBc41AC4AAAAA.Demonskii:BAABLgAECn8mAAMiAAgJPSCaCADZAgAiAAgJPSCaCADZAgAMAAIJAQzmbwBgAAAAAA==.Demton:BAABLgAECn8lAAIiAAgJHB26AwBWAgAiAAgJHB26AwBWAgAAAA==.Denken:BAABLgAFFH8RAAIjAAYJWhbSAgCnAQAjAAYJWhbSAgCnAQAAAA==.Deuslucis:BAAALgADCgEJAQAAAA==.Dezmage:BAAALgADCgYJBgAAAA==.Dezpriest:BAAALgAECgEJAgAAAA==.',
Di='Diagram:BAAALgAECgMJAwAAAA==.Diatonic:BAAALgADCgIJAgABLgAFFAMJBgAMALEaAA==.Dildrathion:BAAALgAECgYJBgAAAA==.Direkau:BAABLgAECn8nAAIWAAkJXCRcAABKAwAWAAkJXCRcAABKAwAAAA==.Divinity:BAAALgAECgYJBgAAAA==.Diwata:BAACLgAFFH8TAAIeAAUJuxfWBgCkAQAeAAUJuxfWBgCkAQAuAAQKfyoAAx4ACQngG3EFAGMCAB4ACQnYG3EFAGMCAB8ABgnNDvs9AEIBAAAA.',
Do='Dogler:BAACLgAFFH8FAAMDAAMJ5B8gEQAWAQADAAMJ5B8gEQAWAQAaAAEJagMAAAAAAAAuAAQKfxkAAwMACAljJIcLAOQCAAMACAljJIcLAOQCABoABgnAGawRAIABAAAA.Dojaz:BAABLgAECn8fAAMMAAkJ5wrgKABDAQAMAAkJ4wrgKABDAQAiAAIJqAmtXwBjAAAAAA==.Doki:BAAALgADCgQJBAAAAA==.Domeydome:BAAALgAECgEJAQAAAA==.Donthitgary:BAAALgAECgIJAgAAAA==.Dooley:BAAALgAECggJEwAAAA==.Doomgrapple:BAAALgADCgMJBQAAAA==.Doriahn:BAAALgAECgYJDAAAAA==.',
Dr='Draconica:BAABLgAECn8bAAISAAgJACArAwDwAgASAAgJACArAwDwAgAAAA==.Dracussy:BAABLgAECn8fAAMRAAkJjBnCEwBGAgARAAkJjBnCEwBGAgASAAIJkA7hNABtAAAAAA==.Dragar:BAABLgAECn8hAAIgAAgJIxdKCwD3AQAgAAgJIxdKCwD3AQAAAA==.Dragonler:BAAALgAECgMJAwABLgAFFAMJBQADAOQfAA==.Dragoon:BAAALgAECgYJBgAAAA==.Draktha:BAAALgAECgQJBAABLgAECgcJFwASAFwjAA==.Dreamchaser:BAAALgAECgQJBAAAAA==.Dreddful:BAAALgAECgEJBAAAAA==.Drkelso:BAABLgAECn8hAAIBAAgJHAwjNwCKAQABAAgJHAwjNwCKAQAAAA==.Dropswitch:BAAALgADCgEJAQAAAA==.Drpeppah:BAAALgADCgMJBAAAAA==.',
Du='Duchalu:BAABLgAECn8lAAIgAAgJ8xOqDQDYAQAgAAgJ8xOqDQDYAQAAAA==.Durtbag:BAAALgADCgQJBwAAAA==.',
Dw='Dwarrfie:BAAALgAECgUJBgAAAA==.',
Dy='Dynabear:BAAALgADCgQJCQAAAA==.',
['Dè']='Dèz:BAABLgAECn8YAAMMAAcJlR0PIgBmAQAMAAcJlR0PIgBmAQAXAAMJmg/mHgCQAAAAAA==.',
['Dú']='Dúncan:BAAALgAECgYJBgAAAA==.',
Ei='Eione:BAABLgAECn8iAAIaAAgJlhf2DAC9AQAaAAgJlhf2DAC9AQAAAA==.',
El='Elaswyn:BAAALgAECgMJBAAAAA==.Elemantary:BAAALgAECgcJCAAAAA==.Elfieras:BAAALgAECgIJAgAAAA==.Elfies:BAAALgADCgYJBwAAAA==.Elinez:BAAALgAECgEJAQAAAA==.Ellcrys:BAABLgAECn8fAAIcAAgJgA1pFwCOAQAcAAgJgA1pFwCOAQAAAA==.Elvinshiznic:BAAALgAECgYJCgAAAA==.Elyzah:BAABLgAECn8YAAMVAAcJXht1IACyAQAVAAcJXht1IACyAQAcAAEJXgjzdQAvAAAAAA==.',
Em='Emagine:BAABLgAECn8kAAIhAAkJliCbAwDRAgAhAAkJliCbAwDRAgAAAA==.Emeraldbeast:BAACLgAFFH8NAAIDAAQJ2RT/DgAoAQADAAQJ2RT/DgAoAQAuAAQKfxwAAgMACAk2G2gaAGcCAAMACAk2G2gaAGcCAAAA.',
En='Enni:BAACLgAFFH8GAAIMAAMJORzUFwAVAQAMAAMJORzUFwAVAQAuAAQKfyAAAgwACAkyJAsQAP4CAAwACAkyJAsQAP4CAAAA.',
Er='Erengarde:BAABLgAECn8eAAIdAAgJAxsjCwAkAgAdAAgJAxsjCwAkAgAAAA==.Eri:BAAALgAECgQJCgAAAA==.Erissra:BAABLgAECn8ZAAMUAAkJAgxWBwDfAQAUAAgJ4wxWBwDfAQAVAAYJygX1swDxAAAAAA==.Eroeda:BAABLgAECn8gAAIiAAgJrQ/5CwB9AQAiAAgJrQ/5CwB9AQAAAA==.',
Es='Escanør:BAAALgAECgQJBQABLgAECgcJDgAPAAAAAA==.',
Ex='Exelero:BAAALgAECgMJCgAAAA==.Exil:BAAALgADCgcJCgAAAA==.Exo:BAABLgAECn8nAAIDAAkJLSQ+AQBqAwADAAkJLSQ+AQBqAwAAAA==.Exosham:BAAALgADCgMJAwABLgAECgkJJwADAC0kAA==.',
Ey='Eynya:BAAALgADCgcJBwABLgAECgQJCAAPAAAAAA==.',
Ez='Ezfrost:BAAALgAFFAEJAQAAAA==.Ezsmash:BAACLgAFFH8FAAIgAAMJQhoVDwANAQAgAAMJQhoVDwANAQAuAAQKfxgAAiAABwmxHQIiAEQCACAABwmxHQIiAEQCAAAA.',
['Eñ']='Eñkei:BAAALgADCgIJAwAAAA==.',
Fa='Faeline:BAAALgAECgMJBQAAAA==.Familiarface:BAAALgAECgYJDQAAAA==.Fastfeet:BAABLgAFFH8IAAIDAAUJJw9KCgBdAQADAAUJJw9KCgBdAQAAAA==.',
Fe='Felam:BAAALgADCgcJBwAAAA==.Ferachio:BAAALgAECgQJBQAAAA==.',
Ff='Ffreshcope:BAAALgAFFAEJAQABLgAFFAUJDAAVAHsXAA==.',
Fi='Fierysquish:BAAALgADCgUJBgAAAA==.Fightinmoose:BAAALgAECgQJBwAAAA==.Fireblitzer:BAAALgAECgMJBAAAAA==.Fistferge:BAAALgAECgcJDQABLgAECgcJGQATABkgAA==.',
Fn='Fnaskmar:BAAALgAECgYJEQAAAA==.',
Fo='Fogpaw:BAAALgADCgkJGAAAAA==.Foosaa:BAAALgAECgYJDgAAAA==.Forbearance:BAABLgAECn8nAAITAAkJNiJwAAD9AgATAAkJNiJwAAD9AgAAAA==.',
Fr='Franco:BAABLgAECn8aAAIFAAkJEQzfHwChAQAFAAkJEQzfHwChAQAAAA==.Freshfresh:BAAALgAECgUJBgABLgAFFAUJDAAVAHsXAA==.Freshlock:BAACLgAFFH8MAAQVAAUJexeqQACmAAAVAAIJlBmqQACmAAAcAAIJYRULEwBZAAAUAAEJAAC/BQAAAAAuAAQKfxkABBwACQkxIkMMAP4BABwABQlcJUMMAP4BABUABgkzH21OAN0BABQABAk/JL8JAKYBAAAA.Frickvicious:BAAALgADCgIJAgAAAA==.Friend:BAAALgAECgEJAgAAAA==.Fright:BAABLgAECn8aAAIIAAgJjRVxVQDhAQAIAAgJjRVxVQDhAQAAAA==.Friska:BAAALgAECgIJAgAAAA==.Frostbolt:BAAALgAECgEJAQAAAA==.Frostcool:BAABLgAECn8YAAIBAAgJwgwfNACVAQABAAgJwgwfNACVAQAAAA==.Frostyh:BAAALgAECgYJCQAAAA==.Frostyp:BAACLgAFFH8MAAILAAQJMgq4CAA2AQALAAQJMgq4CAA2AQAuAAQKfyAAAgsACQmeGSoOAKACAAsACQmeGSoOAKACAAAA.',
Fu='Furion:BAABLgAECn8UAAIgAAYJjRTtTAByAQAgAAYJjRTtTAByAQAAAA==.Furiousbruja:BAAALgAECgQJCQAAAA==.',
Fy='Fyre:BAAALgAECggJDQAAAA==.Fyrebird:BAAALgAECgQJBQABLgAECggJDQAPAAAAAA==.',
Ga='Galadhriel:BAABLgAECn8jAAMDAAgJTRyOGgBlAgADAAgJTRyOGgBlAgAaAAEJVgM7jQAhAAAAAA==.Galadima:BAABLgAECn8jAAIdAAgJaRnhDwDlAQAdAAgJaRnhDwDlAQAAAA==.Galaxywing:BAAALgAECgMJBgAAAA==.Ganador:BAABLgAECn8fAAMVAAkJlBilEwAHAgAVAAcJaRmlEwAHAgAcAAQJNxHfMAD2AAAAAA==.Gayguyender:BAAALgAECgUJDAAAAA==.',
Gb='Gbones:BAAALgAECgEJAQABLgAECgQJBwAPAAAAAA==.',
Ge='Geerah:BAAALgADCgYJBgAAAA==.Gennoro:BAAALgADCgcJBwABLgAECgYJEQAPAAAAAA==.',
Gl='Glizzies:BAABLgAECn8sAAIIAAgJNiQkBQDIAgAIAAgJNiQkBQDIAgAAAA==.Glocky:BAAALgADCgcJBwAAAA==.',
Gn='Gnomeofdeath:BAABLgAECn8aAAICAAgJPCPeFgDyAgACAAgJPCPeFgDyAgAAAA==.',
Go='Gokusan:BAAALgADCgYJBwABLgAECggJIQAVAHYhAA==.Gomgar:BAAALgADCgcJEgAAAA==.Gooned:BAABLgAECn8bAAMNAAgJRRQFCgDJAQANAAgJRRQFCgDJAQAOAAEJWAsXHgA9AAAAAA==.Goonforall:BAAALgADCgEJAQAAAA==.',
Gr='Grampus:BAAALgADCgIJAgABLgADCgYJBgAPAAAAAA==.Grashoppa:BAAALgAECgYJDwAAAA==.Greentide:BAABLgAECn8lAAIhAAkJBx6oDwCbAgAhAAkJBx6oDwCbAgAAAA==.Grengar:BAAALgAECgYJDgAAAA==.Groovybun:BAAALgADCgIJAgAAAA==.Groovymochi:BAABLgAECn8hAAIkAAgJbw0REgCNAQAkAAgJbw0REgCNAQAAAA==.',
Gu='Guccimaybe:BAABLgAECn8fAAIlAAgJ+hHTDAD2AQAlAAgJ+hHTDAD2AQAAAA==.Guldaniel:BAAALgADCgEJAQAAAA==.Guldanramsey:BAABLgAECn8VAAMUAAcJ9hgVCQC2AQAUAAYJPR0VCQC2AQAVAAcJ3g+JfABiAQAAAA==.Gunjá:BAAALgADCgYJCwAAAA==.',
Gw='Gwynastrasza:BAAALgAECgQJCQAAAA==.Gwynneth:BAAALgAECgEJAQABLgAECgQJCQAPAAAAAA==.',
Gx='Gxre:BAAALgAECgkJAgAAAA==.',
['Gò']='Gòku:BAABLgAECn8hAAMVAAgJdiHOBwCQAgAVAAcJdiHOBwCQAgAcAAIJvhF2TACIAAAAAA==.',
['Gö']='Göuf:BAAALgAECgcJBwAAAA==.',
['Gü']='Güy:BAAALgAECgcJDQAAAA==.',
Ha='Halea:BAABLgAECn8YAAIMAAgJpRw1IwB/AgAMAAgJpRw1IwB/AgAAAA==.Haleluya:BAAALgAECgYJCQABLgAECggJGAAMAKUcAA==.Halepurr:BAAALgADCgIJAgABLgAECggJGAAMAKUcAA==.Halogenrofl:BAABLgAECn8bAAIiAAgJgxj3IAC1AQAiAAgJgxj3IAC1AQAAAA==.Hammahtime:BAAALgADCgcJBwAAAA==.Hammerferge:BAABLgAECn8ZAAITAAcJGSChCQA3AgATAAcJGSChCQA3AgAAAA==.Handsofelune:BAAALgAECgQJCAAAAA==.Hannibol:BAAALgADCgYJCAAAAA==.Harrowhark:BAAALgAECgUJDAAAAA==.Hawktwua:BAAALgAFFAEJAQAAAA==.Hawtshot:BAAALgAECgQJBgAAAA==.Hazelena:BAAALgADCgkJFgAAAA==.',
Hb='Hbz:BAABLgAECn8lAAIWAAgJ6BlYBQAJAgAWAAgJ6BlYBQAJAgAAAA==.',
He='Healingbrew:BAABLgAECn8YAAIZAAgJvBjfFgBRAgAZAAgJvBjfFgBRAgAAAA==.Healzplz:BAAALgADCgcJBwAAAA==.Herekittycat:BAAALgAECgEJAQAAAA==.Heretoohelp:BAAALgAECgQJCgAAAA==.',
Hi='Hildar:BAABLgAECn8aAAIdAAcJRBUEEwDAAQAdAAcJRBUEEwDAAQAAAA==.Hillcoast:BAAALgADCgUJBQAAAA==.',
Ho='Holeymoley:BAAALgAECgEJAgAAAA==.Holibeef:BAAALgAECgUJBgABLgAECgYJFwADAE4KAA==.Holybits:BAAALgAECggJEwAAAA==.Holylinoleum:BAAALgADCgQJBAABLgADCggJBgAPAAAAAA==.Holysquish:BAACLgAFFH8OAAIIAAUJtxCQDABXAQAIAAUJtxCQDABXAQAuAAQKfyUAAggACQm4HjMeALYCAAgACQm4HjMeALYCAAAA.Holyz:BAABLgAECn8gAAILAAgJ6BycFgAzAgALAAgJ6BycFgAzAgAAAA==.Homoglobin:BAAALgAFFAMJBAAAAA==.Honeydip:BAABLgAECn8nAAIFAAkJjBezCwBGAgAFAAkJjBezCwBGAgAAAA==.Honésty:BAABLgAECn8cAAIfAAcJChivGgAGAgAfAAcJChivGgAGAgAAAA==.Hoontertile:BAAALgADCgcJBwAAAA==.Horsegirl:BAAALgADCggJCAAAAA==.Hotfistbaby:BAAALgAECgcJCgAAAA==.Hotspankyboi:BAABLgAECn8UAAITAAgJRSbyAABjAwATAAgJRSbyAABjAwAAAA==.',
Hr='Hruun:BAAALgADCgcJBwAAAA==.',
Hu='Huntskii:BAAALgAECgQJBgAAAA==.Hussle:BAAALgADCggJDgAAAA==.',
Ic='Iceicebabye:BAAALgAECgQJCAAAAA==.Iceleaf:BAAALgADCgYJBQAAAA==.Iciest:BAAALgAECgMJAgABLgAECggJLAAIADYkAA==.',
Ig='Iger:BAAALgADCgcJDwAAAA==.',
Ih='Iha:BAAALgADCgIJAwAAAA==.',
Ij='Ijudgepeople:BAAALgADCggJCAABLgAECgIJAgAPAAAAAA==.',
Ik='Ikkaroas:BAAALgAECgUJBQAAAA==.Ikkis:BAAALgAECgUJCQAAAA==.Ikmoti:BAAALgAECgEJAQAAAA==.',
Il='Ileinaa:BAABLgAECn8wAAIfAAkJ1RHtHwDiAQAfAAkJ1RHtHwDiAQAAAA==.Iliketrains:BAABLgAECn8iAAIjAAgJnh13BQBeAgAjAAgJnh13BQBeAgAAAA==.Illuminatì:BAAALgAECgYJDwAAAA==.Ilovegrizzly:BAAALgAECgEJAQABLgAECgEJAgAPAAAAAA==.',
Im='Immortalhulk:BAAALgADCgIJAgAAAA==.',
In='Indicud:BAAALgAECgUJCwAAAA==.Inoxiakek:BAAALgAECgQJCAAAAA==.Intensedh:BAAALgAECgYJDgABLgAECgcJFQAhAC0eAA==.Intensevok:BAAALgADCgcJBwABLgAECgcJFQAhAC0eAA==.Intensifiedx:BAABLgAECn8VAAIhAAcJLR4QHgArAgAhAAcJLR4QHgArAgAAAA==.',
Is='Iscreamalot:BAABLgAECn8fAAIgAAgJAhkEGQCDAgAgAAgJAhkEGQCDAgAAAA==.Isele:BAAALgAECgQJBAABLgAECgYJCgAPAAAAAA==.',
It='Itybity:BAAALgAECgYJCwAAAA==.',
Iy='Iyatsuki:BAAALgAFFAIJAwAAAA==.',
Ja='Jawbone:BAAALgADCgEJAQAAAA==.Jayfizzle:BAAALgAECgEJAgAAAA==.Jaymazing:BAABLgAECn8aAAIMAAkJ7CF1BQCKAgAMAAkJ7CF1BQCKAgABLgAECgEJAgAPAAAAAA==.',
Ji='Jimmyboy:BAAALgADCgUJBQAAAA==.',
Jo='Joenormousgg:BAAALgADCgUJBQAAAA==.Johnathan:BAAALgADCgEJAQAAAA==.Johnconner:BAAALgAECgYJCwAAAA==.Jonald:BAAALgAECgQJBgABLgAECgcJGwAZAD0ZAA==.Jongwoo:BAAALgADCgYJCAAAAA==.Jonthecron:BAABLgAECn8bAAMZAAcJPRl0EQCCAQAZAAcJPRl0EQCCAQAmAAEJ1BFDegA2AAAAAA==.Joojekabab:BAAALgADCgEJAQAAAA==.Jorkinit:BAAALgAECggJEwAAAA==.Jormot:BAAALgAECgEJAQABLgAECggJDQAPAAAAAA==.Jorok:BAABLgAECn8VAAIjAAkJhBXbHAAqAgAjAAkJhBXbHAAqAgAAAA==.',
Ju='Jubilee:BAABLgAECn8hAAIVAAkJFRncIwCEAgAVAAkJFRncIwCEAgAAAA==.Jumannji:BAABLgAECn8fAAIjAAkJAh20BAByAgAjAAkJAh20BAByAgAAAA==.Jurik:BAAALgADCgUJDgAAAA==.Justadragon:BAAALgADCgIJAwAAAA==.',
Ka='Kabluey:BAAALgADCgEJAQAAAA==.Kalarm:BAAALgADCgYJBgAAAA==.Kallidan:BAABLgAECn8TAAIMAAkJiRNuMQA1AgAMAAkJiRNuMQA1AgAAAA==.Kallight:BAAALgAECgcJBwAAAA==.Karks:BAACLgAFFH8JAAMgAAMJSx1yFgC7AAAgAAIJ6BtyFgC7AAAnAAEJEiDcCABjAAAuAAQKfx8AAyAACQmEH3sUAKoCACAACQkCG3sUAKoCACcAAwkRGaofAPEAAAAA.Karsaørlong:BAAALgAECgEJAQAAAA==.Kassabekkaia:BAAALgADCggJDgABLgAECgcJEwAPAAAAAA==.Katrois:BAAALgAECgYJBgAAAA==.Kayem:BAAALgADCgIJAgAAAA==.Kazroth:BAAALgADCgcJDQAAAA==.',
Kb='Kbe:BAAALgADCgQJBAAAAA==.',
Ke='Kelewan:BAABLgAECn8lAAMCAAgJ2BZDNgBgAQAYAAcJZBaoFgCrAQACAAgJmQpDNgBgAQAAAA==.Kellabrimbor:BAAALgADCgUJBQAAAA==.Kellelor:BAAALgAECgEJAwAAAA==.Kerrigan:BAAALgAECgEJAQABLgAECgYJCAAPAAAAAA==.',
Ki='Killkillkill:BAAALgAECgYJBgAAAA==.Kindassuddy:BAABLgAECn8nAAMQAAkJCh9rAAB+AgABAAgJYiCXKgDIAgAQAAkJJBZrAAB+AgAAAA==.Kindled:BAABLgAECn8VAAIBAAgJlxayawD+AQABAAgJlxayawD+AQAAAA==.Kinvardar:BAAALgAECgcJEwAAAA==.Kirbbslav:BAAALgADCgEJAQABLgAFFAYJEwAdAA8ZAA==.Kirbislav:BAAALgAECgYJEgABLgAFFAYJEwAdAA8ZAA==.Kirbslav:BAACLgAFFH8TAAIdAAYJDxlYBACbAQAdAAYJDxlYBACbAQAuAAQKfycAAh0ACQmWI6MEACMDAB0ACQmWI6MEACMDAAAA.Kirbyslav:BAAALgAFFAIJAgABLgAFFAYJEwAdAA8ZAA==.Kirkland:BAAALgAECgIJAgAAAA==.Kirklandbeef:BAAALgAECgIJAgAAAA==.Kits:BAAALgAECgEJAQABLgAECggJFAAIAH0OAA==.',
Kn='Kniavez:BAAALgAECgcJEgAAAA==.',
Ko='Koranova:BAAALgAECgcJDQAAAA==.Korro:BAABLgAECn8mAAIKAAgJ9B7KAgB5AgAKAAgJ9B7KAgB5AgAAAA==.Kostin:BAABLgAECn8fAAIgAAgJ/RdsHgBcAgAgAAgJ/RdsHgBcAgAAAA==.',
Kr='Krak:BAAALgAECgYJEAAAAA==.Krasta:BAAALgAECgMJBgAAAA==.Kratosdh:BAAALgADCgMJBAAAAA==.Krolow:BAACLgAFFH8UAAIgAAUJkhY5CQBLAQAgAAUJkhY5CQBLAQAuAAQKfyQAAxYACAnqG1kHAMwBACAABwlOH6kjADgCABYACAnjF1kHAMwBAAAA.Kruugh:BAABLgAECn8ZAAIjAAYJ+hfmIAAUAQAjAAYJ+hfmIAAUAQAAAA==.',
Ku='Kuler:BAABLgAECn8fAAIgAAgJ5x3bFACmAgAgAAgJ5x3bFACmAgAAAA==.Kungfushrub:BAAALgAECgcJEwAAAA==.Kuulandor:BAABLgAECn8lAAIYAAkJOyGSAwAfAwAYAAkJOyGSAwAfAwAAAA==.',
['Kè']='Kèèn:BAACLgAFFH8KAAIIAAMJIR6KDwAsAQAIAAMJIR6KDwAsAQAuAAQKfxQAAggABgliI3RcAM0BAAgABgliI3RcAM0BAAAA.',
['Ké']='Két:BAABLgAECn8ZAAIDAAgJzxoaJwAaAgADAAgJzxoaJwAaAgAAAA==.',
['Kê']='Kêt:BAAALgAECgMJBgABLgAECggJGQADAM8aAA==.',
['Kí']='Kítkat:BAABLgAECn8UAAIIAAgJfQ5fKwCUAQAIAAgJfQ5fKwCUAQAAAA==.',
['Kÿ']='Kÿra:BAAALgAECgEJAQAAAA==.',
Le='Leesin:BAAALgAECgEJAQAAAA==.Levelground:BAAALgAFFAIJAgAAAA==.Lewd:BAAALgAECgMJBAABLgAECggJGAAMAKUcAA==.Leylines:BAAALgADCgcJBwAAAA==.',
Li='Liakä:BAAALgADCgYJBgAAAA==.Lightrampant:BAAALgADCgMJAQAAAA==.Lilmonkey:BAAALgADCgQJBgAAAA==.Limegreen:BAAALgADCgEJAQAAAA==.Liquidsevenz:BAABLgAECn8gAAIlAAcJvBO9BgCYAQAlAAcJvBO9BgCYAQAAAA==.Litlit:BAAALgAECgYJCgAAAA==.',
Lo='Lodoss:BAABLgAECn8pAAIhAAgJEhzcBwBtAgAhAAgJEhzcBwBtAgAAAA==.Lollipops:BAAALgAECgEJAQAAAA==.Lonah:BAAALgAECggJCQABLgAFFAMJBQAIAPgZAA==.Lorienb:BAABLgAECn8lAAMLAAgJkhhFDAC8AQALAAgJkhhFDAC8AQAeAAIJbRCMSQByAAAAAA==.Lotheran:BAAALgADCgEJAQAAAA==.Lothé:BAAALgAECgQJBAAAAA==.Lotlizar:BAAALgADCgEJAQABLgAECgcJFgACACgJAA==.Lowkydead:BAAALgADCgQJBQAAAA==.',
Lu='Lubelesso:BAAALgADCgkJFgAAAA==.Luckehlock:BAACLgAFFH8LAAIUAAUJlyENAAAIAgAUAAUJlyENAAAIAgAuAAQKfyAAAxQACQlwJAsAAN4DABQACQlwJAsAAN4DABUAAQlvAKc0ARIAAAEuAAUUBgkGABEANBYA.Luckehtwo:BAABLgAFFH8GAAIRAAYJNBZdBgCPAQARAAYJNBZdBgCPAQAAAA==.Luxcn:BAABLgAECn8bAAMFAAgJ3xX0FQDiAQAFAAgJ3xX0FQDiAQAGAAEJggTFJAAqAAAAAA==.',
Ma='Macgibbins:BAABLgAECn8ZAAIKAAgJ+xQSCQDRAQAKAAgJ+xQSCQDRAQAAAA==.Madepure:BAAALgAECgMJAwABLgAECggJLAAIADYkAA==.Magus:BAABLgAECn8XAAMBAAcJpCOuKgC5AQABAAcJpCOuKgC5AQAQAAIJ4xITDABuAAABLgAFFAYJEgAaAAMcAA==.Mahyora:BAAALgAECgEJBAAAAA==.Mavus:BAAALgAECgYJEwAAAA==.',
Mc='Mccream:BAAALgAECgMJAwAAAA==.',
Me='Melylen:BAAALgAECgQJCAAAAA==.Mezugyouzug:BAAALgADCgQJBAAAAA==.',
Mi='Milkbolt:BAAALgAECgYJEQAAAA==.Milkhoundttv:BAABLgAECn8aAAIDAAYJlAxTQADPAAADAAYJlAxTQADPAAAAAA==.Minigolf:BAABLgAECn8fAAMMAAcJ6xleHgB8AQAMAAcJExleHgB8AQAiAAUJWRnDMABLAQAAAA==.Minigun:BAAALgAECgcJEwAAAA==.Minioozy:BAAALgADCgUJBQAAAA==.Minivan:BAAALgADCgQJBAABLgAECggJHwAMAOsZAA==.Misawa:BAAALgAECgcJDQAAAA==.Mizuboxx:BAABLgAECn8eAAIdAAgJQCLNAgDkAgAdAAgJQCLNAgDkAgAAAA==.',
Mo='Molyver:BAABLgAECn8lAAMmAAkJGRdRJgClAQAmAAcJJhNRJgClAQAkAAUJcwy9IQDxAAAAAA==.Momak:BAAALgAECgQJBAABLgAECgYJCQAPAAAAAA==.Mommey:BAAALgAECgUJBQAAAA==.Monteloco:BAAALgADCgkJCQAAAA==.Moonfrost:BAAALgADCgYJBwAAAA==.Moonkitty:BAAALgADCgEJAQAAAA==.Moonmane:BAABLgAECn8UAAIaAAcJExiMEACNAQAaAAcJExiMEACNAQAAAA==.Moonmellow:BAAALgAECgYJBwAAAA==.Moosin:BAAALgAECgEJAgAAAA==.Mozgus:BAABLgAECn8cAAIfAAcJDCIXEwBHAgAfAAcJDCIXEwBHAgAAAA==.',
Mu='Munder:BAAALgAECgUJDAAAAA==.Murdurio:BAAALgAECgQJCwAAAA==.Musculate:BAAALgAECgkJEgAAAA==.',
Mx='Mxdi:BAABLgAECn8hAAQDAAkJeSI9AQBqAwADAAkJeSI9AQBqAwAaAAEJ9BLleQA+AAAJAAEJzQ3nNgArAAAAAA==.',
My='Myranda:BAAALgADCgMJAwAAAA==.',
Na='Nazdarok:BAAALgAECgMJBAAAAA==.Nazenoth:BAAALgADCgUJDgAAAA==.Nazgûl:BAABLgAECn8aAAIXAAcJ4B7qAwDDAQAXAAcJ4B7qAwDDAQAAAA==.',
Ne='Necrofearlia:BAABLgAECn8XAAQVAAgJpBMXIAC1AQAVAAgJrxAXIAC1AQAUAAQJjBh+DwA3AQAcAAMJqAoPTQCGAAAAAA==.Nensha:BAAALgAECgYJDwAAAA==.Nethys:BAABLgAECn8sAAMLAAkJrh3XAQDNAgALAAkJrh3XAQDNAgAeAAEJnAX7XAAoAAAAAA==.',
Ni='Nick:BAACLgAFFH8SAAIaAAYJAxwFAwCbAQAaAAYJAxwFAwCbAQAuAAQKfygABBoACQkeJF0CAJwDABoACQkeJF0CAJwDACgABgmmIFcIACgCAAMAAQnBCO3HADoAAAAA.Nightxangel:BAAALgADCgcJBwAAAA==.',
No='Noctrimm:BAAALgADCgEJAQAAAA==.Nolyt:BAABLgAECn8aAAICAAcJrgq5RwAnAQACAAcJrgq5RwAnAQAAAA==.Nonna:BAABLgAECn8dAAInAAgJkB1sBQCFAgAnAAgJkB1sBQCFAgAAAA==.Noolore:BAACLgAFFH8SAAMCAAUJlB07GgBNAQACAAQJlB07GgBNAQAYAAEJAACBJQAAAAAuAAQKfyYAAgIACQm1IV8XAO8CAAIACQm1IV8XAO8CAAAA.Norandil:BAAALgAECgQJBQAAAA==.Notendela:BAAALgAECgEJAQABLgAECgYJCgAPAAAAAA==.',
Nu='Nuiria:BAAALgADCgUJBQAAAA==.Nurfgun:BAABLgAECn8bAAMFAAcJXCEMDABBAgAFAAcJ9h8MDABBAgAGAAYJ/yLhHQA1AgABLgAECggJCgAPAAAAAA==.Nurfroll:BAAALgAECggJCgAAAA==.Nurfstrasza:BAAALgADCgYJBgABLgAECggJCgAPAAAAAA==.',
Nw='Nwahher:BAAALgADCgUJBwAAAA==.',
Of='Offleash:BAAALgADCggJBwAAAA==.',
Om='Ominous:BAAALgADCgYJBgAAAA==.',
On='Onlock:BAAALgADCgYJBgAAAA==.Onlyfrost:BAAALgADCgcJCQAAAA==.Onlyslams:BAABLgAECn8eAAIZAAgJqRwsFwBNAgAZAAgJqRwsFwBNAgABLgAFFAMJBQADAHMQAA==.',
Op='Opheliana:BAAALgADCgEJAQAAAA==.',
Or='Orcsmash:BAAALgAECgQJDAAAAA==.',
Ow='Owlwithahat:BAAALgADCgcJDQAAAA==.',
Ox='Oxen:BAABLgAECn8jAAQCAAgJniEdFgAJAgAYAAgJ5x7YCQB+AgACAAgJnRsdFgAJAgAEAAEJbw0WFwA0AAAAAA==.',
Pa='Padraig:BAAALgADCgcJBwAAAA==.Passoot:BAAALgAECgEJBgAAAA==.',
Pe='Pega:BAAALgADCgQJBAABLgAECggJJQAlAFciAA==.Pegah:BAAALgAECgMJAwAAAA==.Pege:BAABLgAECn8lAAIlAAgJVyI9AwAAAwAlAAgJVyI9AwAAAwAAAA==.Penniee:BAAALgAECgMJBAAAAA==.Penniwing:BAABLgAECn8nAAQRAAkJYBwMHADoAQARAAcJgxoMHADoAQAHAAkJYgsaHgCRAQASAAEJ0hKjQAAvAAAAAA==.Percival:BAECLgAFFH8XAAIKAAYJHh81AAABAgAKAAYJHh81AAABAgAuAAQKfyAABAoACQlcI0EAAMQDAAoACQlcI0EAAMQDAAYABQnNHN1MAB0BAAUAAwmVI/adAJQAAAAA.',
Ph='Phaedra:BAAALgAECgkJMQAAAQ==.Phanuel:BAABLgAECn8VAAIBAAYJSQ3rzABQAQABAAYJSQ3rzABQAQABLgAFFAMJCgAIACEeAA==.Phealvoker:BAAALgADCgIJAgABLgADCgkJCgAPAAAAAA==.',
Pi='Piffboy:BAABLgAECn8WAAMIAAgJsRGKUADwAQAIAAgJsRGKUADwAQAdAAMJ+gcTNgCjAAAAAA==.Pissvibe:BAAALgAECgcJBwAAAA==.Pixr:BAAALgAECgcJAQAAAA==.',
Po='Powrwordaddy:BAAALgADCgkJEQABLgAECgcJEwAPAAAAAA==.',
Pr='Priestler:BAABLgAECn8fAAQeAAgJ4x5sCQCkAgAeAAgJ4x5sCQCkAgALAAcJgxrIHAD1AQAfAAQJFQXmiwADAAABLgAFFAMJBQADAOQfAA==.Primeape:BAABLgAECn8VAAMYAAcJlAyoEwDpAAAYAAcJxwmoEwDpAAACAAIJ7xNRBgFqAAAAAA==.Prodigal:BAAALgADCgUJBQAAAA==.',
Pu='Pullbarg:BAAALgAECgUJCQAAAA==.Pumpies:BAABLgAECn8WAAIHAAUJmRNdDwAJAQAHAAUJmRNdDwAJAQAAAA==.Punchdrunk:BAAALgADCgYJDQAAAA==.Purrdruid:BAAALgADCgUJBQAAAA==.',
Py='Pyru:BAAALgADCgYJBgAAAA==.',
['Pà']='Pàngde:BAAALgAECgIJAgAAAA==.',
['Pï']='Pïng:BAABLgAECn8cAAIFAAcJGxDQNQA6AQAFAAcJGxDQNQA6AQAAAA==.',
Qu='Quickkwinter:BAAALgAECgEJAgAAAA==.Quickly:BAAALgAECgQJBQAAAA==.',
Ra='Raantoks:BAAALgADCggJCgAAAA==.Rachet:BAAALgAECgYJDwAAAA==.Raelilblack:BAAALgAECgYJBwAAAA==.Raideñ:BAAALgAECgIJAwAAAA==.Rakhár:BAAALgAECgcJBwAAAA==.Raner:BAAALgADCgMJAwABLgAECgcJIwAmAO8fAA==.Rashala:BAAALgAECgQJDwAAAA==.Raucahann:BAAALgAECgEJAgAAAA==.Rayado:BAAALgAECgYJDQAAAA==.Razarke:BAABLgAECn8XAAISAAcJXCMRBQCxAgASAAcJXCMRBQCxAgAAAA==.',
Re='Reggienoble:BAACLgAFFH8IAAIKAAMJlRzABwAdAQAKAAMJlRzABwAdAQAuAAQKfx8AAgoACAkWJHcCABcDAAoACAkWJHcCABcDAAAA.Rekerî:BAAALgAECgkJDwAAAA==.Reverendmini:BAAALgAECgMJAwAAAA==.Reynaria:BAACLgAFFH8GAAIkAAMJRh1XDQAHAQAkAAMJRh1XDQAHAQAuAAQKfyEAAyQACAlLIC0JAMACACQACAlLIC0JAMACACYABAlbFFJJAO4AAAAA.Reyyne:BAACLgAFFH8KAAIdAAMJ+R57DQAjAQAdAAMJ+R57DQAjAQAuAAQKfycAAh0ACAmtIg4JAN8CAB0ACAmtIg4JAN8CAAAA.',
Ri='Richmage:BAAALgAECgMJBAABLgAFFAUJEAAFAE4dAA==.Rimetail:BAAALgAECgcJDQAAAA==.Rinzee:BAAALgAECgQJBgAAAA==.Rinzlrr:BAAALgAECgUJCAABLgAECgcJIwAmAO8fAA==.Rioroute:BAAALgADCgkJEQAAAA==.Rivett:BAAALgADCgUJBQAAAA==.',
Ro='Roelson:BAAALgADCgEJAQAAAA==.Roflock:BAAALgADCgEJAQAAAA==.Rohrn:BAABLgAECn8XAAIIAAYJ8xRlSgArAQAIAAYJ8xRlSgArAQAAAA==.Rol:BAACLgAFFH8KAAIeAAQJ8g/5DQAuAQAeAAQJ8g/5DQAuAQAuAAQKfxkABB8ACQkWHWEKAKcCAB8ACAn8HWEKAKcCAB4ABQmkFQ8wAB8BAAsABAlfGFRBAO4AAAAA.Rolius:BAAALgADCgQJBAAAAA==.Rosenylund:BAAALgAECgYJEgAAAA==.Rotfist:BAAALgADCgUJBQABLgAECgcJFgACACgJAA==.',
Ry='Rydia:BAAALgADCgQJBAAAAA==.',
Sa='Safa:BAAALgAECgYJCgABLgAECggJGgABALkbAA==.Saintjudas:BAAALgAECgEJAQAAAA==.Saintsnetie:BAAALgAECgQJCAAAAA==.',
Sc='Scottyknows:BAAALgADCgYJBgAAAA==.Scottymaybe:BAAALgAECggJDgAAAA==.Scredwin:BAABLgAECn8hAAMcAAgJlhuBAQAwAgAcAAgJlhuBAQAwAgAVAAEJOQOMKQEoAAAAAA==.',
Se='Seancody:BAAALgADCgUJBQAAAA==.Senorbobo:BAABLgAECn8kAAIWAAgJDx7HCACSAgAWAAgJDx7HCACSAgAAAA==.Serenian:BAAALgAECgYJCwAAAA==.Serni:BAAALgAECgYJCQAAAA==.',
Sh='Shadora:BAAALgAECgYJDwAAAA==.Shadowsbane:BAAALgADCgUJBQAAAA==.Shadowslite:BAAALgAECgEJAQAAAA==.Shadowwolf:BAABLgAECn8dAAIDAAcJIxDlUABiAQADAAcJIxDlUABiAQAAAA==.Sham:BAABLgAECn8pAAMVAAgJ8iBiBwCXAgAVAAgJ8iBiBwCXAgAcAAIJ5A9mWABlAAAAAA==.Shamios:BAABLgAECn8YAAIDAAgJ5CCDEQCqAgADAAgJ5CCDEQCqAgAAAA==.Shammknight:BAAALgADCgQJBAAAAA==.Shanksinatrá:BAACLgAFFH8XAAMNAAYJJh0rAgDiAQANAAUJdB4rAgDiAQAOAAMJnRDHAgAJAQAuAAQKfygAAw0ACQljJncBAK4DAA0ACQlSJncBAK4DAA4ABAlRGnoPABkBAAAA.Shaquira:BAAALgAECgYJDQAAAA==.Shatt:BAAALgAECgYJBwAAAA==.Shaxxi:BAAALgAECgYJEQAAAA==.Shedari:BAAALgADCgkJEgAAAA==.Shephrah:BAABLgAECn8lAAMkAAkJ/wuQFwBNAQAkAAkJ/wuQFwBNAQAZAAMJRAVBNwB9AAAAAA==.Shiftalic:BAAALgAFFAEJAQABLgAFFAIJAgAPAAAAAA==.Shifter:BAAALgAECgYJEAAAAA==.Shoshanna:BAAALgAECgIJAgAAAA==.Shourioom:BAACLgAFFH8FAAIIAAMJ+Bn/GgALAQAIAAMJ+Bn/GgALAQAuAAQKfyQAAggACAkxJVAIAFEDAAgACAkxJVAIAFEDAAAA.Shourix:BAABLgAECn8dAAIgAAcJ0yEhEwC2AgAgAAcJ0yEhEwC2AgABLgAFFAMJBQAIAPgZAA==.Shploople:BAAALgAECgQJCQAAAA==.Shuckle:BAAALgAECgQJBAABLgAFFAYJEgAaAAMcAA==.Shuppet:BAAALgADCgUJDAAAAA==.',
Si='Sifuicyhot:BAAALgAECgcJDgAAAA==.Sihnn:BAAALgAECgYJBwAAAA==.Simzerker:BAACLgAFFH8OAAIgAAUJVCNdAQD0AQAgAAUJVCNdAQD0AQAuAAQKfxsAAiAACAmHIlkHADMDACAACAmHIlkHADMDAAAA.',
Sk='Skwinkles:BAAALgADCgEJAQAAAA==.',
Sl='Slambulance:BAAALgADCgIJAgAAAA==.Sleepington:BAAALgAECgMJAwAAAA==.Slickrick:BAAALgAECgMJBAAAAA==.Slikshotgrey:BAAALgADCgQJBAAAAA==.Slyvex:BAAALgADCgYJCgAAAA==.',
Sm='Smûsh:BAAALgADCgIJAgAAAA==.',
Sn='Snackum:BAAALgADCgYJBgAAAA==.Snarfca:BAAALgAECgQJBAAAAA==.Sneakthief:BAAALgADCgYJBwAAAA==.Sniiffle:BAABLgAECn8gAAIDAAcJhRydEwDrAQADAAcJhRydEwDrAQAAAA==.Snowmage:BAABLgAECn8kAAMbAAgJMSBXAQDKAgAbAAgJMSBXAQDKAgAQAAEJugfQEAAwAAAAAA==.',
So='Soarscha:BAAALgAECgEJAQAAAA==.Softly:BAACLgAFFH8MAAIkAAYJOxXaAQARAgAkAAYJOxXaAQARAgAuAAQKfzkAAiQACQlrJjwAAOcDACQACQlrJjwAAOcDAAAA.Sokan:BAAALgADCgUJBwAAAA==.Somecutty:BAAALgADCgEJAQAAAA==.',
Sp='Spellbeard:BAAALgADCggJBwAAAA==.Spellcrackle:BAAALgADCgkJEQABLgAECgYJFwADAE4KAA==.Sploosh:BAAALgADCgEJAQAAAA==.Spùd:BAAALgAECgEJAQAAAA==.',
Sq='Squa:BAACLgAFFH8JAAMNAAMJUiU5CQBLAQANAAMJUiU5CQBLAQAOAAIJ3gkCBAC1AAAuAAQKfx8AAw0ACAmmIqIKAOgCAA0ACAmmIqIKAOgCAA4ABAlyHHgMAFwBAAAA.Squishdemon:BAAALgADCgEJAQAAAA==.Squî:BAAALgAFFAEJAQABLgAFFAMJCQANAFIlAA==.',
Ss='Ssudds:BAAALgAECgYJCwABLgAECgkJJwAQAAofAA==.Ssuddychan:BAAALgAECggJEgABLgAECgkJJwAQAAofAA==.',
St='Stalagstrype:BAABLgAECn8UAAIIAAgJ6B2WDwBBAgAIAAgJ6B2WDwBBAgAAAA==.Stankfu:BAAALgADCgQJBAAAAA==.Starkisses:BAABLgAECn8mAAIFAAkJWx89BAC9AgAFAAkJWx89BAC9AgAAAA==.Steeb:BAAALgAECgQJBAAAAA==.Stenkeydk:BAABLgAECn8jAAMCAAgJbBOqNQBjAQACAAgJbBOqNQBjAQAEAAEJGgLREgAjAAAAAA==.Steve:BAAALgAECgQJBAABLgAECgIJAgAPAAAAAA==.Stonepaw:BAAALgADCgQJBAAAAA==.Storebrand:BAAALgADCgcJCAABLgAECgIJAgAPAAAAAA==.Storebrandps:BAAALgADCgYJBwABLgAECgIJAgAPAAAAAA==.Stratego:BAAALgADCgUJDgAAAA==.Styrthe:BAACLgAFFH8ZAAQZAAYJkB4uBQCCAQAZAAUJnhwuBQCCAQAkAAIJ8xeoGQBlAAAmAAEJKASOGQA/AAAuAAQKfyAAAxkACQmDGfMRAIUCABkACQmDGfMRAIUCACQABwlFEC8uAEcBAAAA.',
Su='Subotae:BAAALgADCgMJAwAAAA==.Surfacing:BAAALgAECgcJDQAAAA==.Surventval:BAAALgAECgYJEQABLgAECgcJIwAmAO8fAA==.',
Sw='Swindler:BAABLgAECn8YAAMCAAcJjiAeFAAYAgACAAcJjiAeFAAYAgAYAAYJIhUBHQBiAQAAAA==.Swollstone:BAAALgAECgYJEwAAAA==.',
Sy='Symphony:BAACLgAFFH8GAAIMAAMJsRq8GgAGAQAMAAMJsRq8GgAGAQAuAAQKfyMAAgwACAlcHckLACICAAwACAlcHckLACICAAAA.Syzegy:BAAALgAECgEJAwAAAA==.',
Ta='Taeka:BAAALgAECgQJBwAAAA==.Talkimas:BAABLgAECn8lAAQGAAgJYxphGwBKAgAGAAgJNBphGwBKAgAKAAgJxxD2CQDCAQAFAAEJAAAlwQBDAAAAAA==.Talvisota:BAABLgAECn8kAAICAAgJDSGfBwClAgACAAgJDSGfBwClAgAAAA==.Tankthor:BAABLgAECn8jAAMgAAgJIxGxDgDLAQAgAAgJGRGxDgDLAQAWAAcJcgnnIgAnAQAAAA==.Tarirn:BAACLgAFFH8IAAICAAIJSx18SgCtAAACAAIJSx18SgCtAAAuAAQKfxQAAgIACAl+G4BSAPoBAAIACAl+G4BSAPoBAAAA.Tazgrim:BAAALgAECgYJDwAAAA==.',
Te='Teflondon:BAAALgADCgQJBwAAAA==.Teknar:BAAALgADCgQJBAAAAA==.Tekos:BAAALgAECgQJBQABLgAFFAQJCgAiACQSAA==.Tekoslul:BAACLgAFFH8KAAIiAAQJJBKCAwBZAQAiAAQJJBKCAwBZAQAuAAQKfxkAAyIACQkBJDICAHQDACIACQkBJDICAHQDAAwABAmXFjCPAAIBAAAA.Tekosp:BAAALgAECgMJBAABLgAFFAQJCgAiACQSAA==.Tekosxd:BAAALgAECgEJAwABLgAFFAQJCgAiACQSAA==.Telawolf:BAAALgADCggJCAAAAA==.Teldrussy:BAAALgAECggJCAAAAA==.Telorian:BAABLgAECn8YAAIMAAgJpx7zJAB1AgAMAAgJpx7zJAB1AgAAAA==.Tendeda:BAAALgAECgQJBAAAAA==.Terrasite:BAAALgAECgQJBAAAAA==.',
Th='Thalunar:BAABLgAECn8XAAIFAAgJAhq7JAAqAgAFAAgJAhq7JAAqAgAAAA==.Thatonedruid:BAAALgADCgUJBQABLgAECggJJAAWAA8eAA==.Thejw:BAAALgAECgYJEgAAAA==.Thrallzballz:BAAALgADCgYJBgAAAA==.Thrdeyethump:BAAALgAECgYJCQAAAA==.Thörck:BAAALgAECggJDQAAAA==.',
Ti='Tigersu:BAAALgAFFAEJAQAAAA==.Tinklewinkle:BAABLgAECn8oAAIbAAkJMiEdAAAMAwAbAAkJMiEdAAAMAwAAAA==.Titanrb:BAAALgADCgcJCwAAAA==.',
Tj='Tjaili:BAAALgAECgcJDwAAAA==.',
To='Tocks:BAAALgAECgQJBQAAAA==.Toco:BAAALgAECgEJAQABLgAECgYJHgAjAEMiAA==.Toge:BAABLgAECn8VAAMBAAgJjSEzOQCRAgABAAgJjSEzOQCRAgAbAAEJ9AzvHgAzAAABLgAFFAYJEQAjAFoWAA==.Tokapolo:BAABLgAECn8eAAIjAAYJQyKtDgC2AQAjAAYJQyKtDgC2AQAAAA==.Topshelfelf:BAABLgAECn8kAAMeAAgJVBNuDwCWAQAeAAgJVBNuDwCWAQAfAAEJnwONiAAnAAAAAA==.Torver:BAAALgAECggJEgAAAA==.Totemsquish:BAAALgADCgEJAQAAAA==.',
Tr='Treemother:BAABLgAECn8iAAIDAAYJRRwHMwDdAQADAAYJRRwHMwDdAQAAAA==.Treewa:BAAALgAFFAEJAgAAAA==.Tresdin:BAACLgAFFH8GAAIIAAQJKAgCFgAnAQAIAAQJKAgCFgAnAQAuAAQKfxkAAggACAmzF3ZAACQCAAgACAmzF3ZAACQCAAAA.',
Ts='Tsohg:BAAALgADCgYJCAAAAA==.',
Tu='Tuhalla:BAABLgAECn8bAAIIAAgJWgvRPgBNAQAIAAgJWgvRPgBNAQAAAA==.Tumlock:BAABLgAECn8iAAMcAAcJSAxaCwDrAAAVAAcJxgkXUgD6AAAcAAYJ+wlaCwDrAAAAAA==.Turbulence:BAAALgAECgQJBAAAAA==.',
Tw='Twl:BAAALgAECgQJBgAAAA==.',
['Tï']='Tïgra:BAABLgAECn8lAAIMAAgJJx92CABSAgAMAAgJJx92CABSAgAAAA==.',
Ua='Uandikillhim:BAABLgAECn8fAAIeAAgJrB4oCAC9AgAeAAgJrB4oCAC9AgAAAA==.',
Ul='Uldren:BAAALgAECgIJAgABLgAECgkJKQANABIdAA==.',
Un='Uncompetent:BAAALgADCgEJAQAAAA==.Undeadbones:BAAALgAECgQJBwAAAA==.Unfading:BAABLgAECn8lAAIIAAgJih3mFQALAgAIAAgJih3mFQALAgAAAA==.Unholyknight:BAAALgAECgYJBgAAAA==.Uninfluenced:BAAALgAECgQJBQAAAA==.Unoo:BAAALgADCgMJAwAAAA==.',
Ur='Uranus:BAABLgAECn8aAAIFAAYJqx5nHwCkAQAFAAYJqx5nHwCkAQAAAA==.Urban:BAAALgADCgEJAQAAAA==.Urtark:BAABLgAECn8lAAIgAAkJhh5bCQAUAgAgAAkJhh5bCQAUAgAAAA==.',
Va='Vadym:BAAALgAECgMJBQAAAA==.Vaelia:BAAALgAECggJDQAAAA==.Vainquish:BAAALgAECgYJCgAAAA==.Valeriann:BAAALgADCgMJAwAAAA==.Valorias:BAABLgAECn8bAAIeAAgJ9RnoDABqAgAeAAgJ9RnoDABqAgAAAA==.Vankwish:BAABLgAECn8eAAMBAAcJuxYKNQCRAQABAAcJpRUKNQCRAQAbAAYJFxTYBwB/AQAAAA==.Vanquith:BAAALgAECgEJAQAAAA==.Varalic:BAAALgAFFAIJAgAAAA==.Varandra:BAAALgADCgMJAwABLgAECgIJAgAPAAAAAA==.Vaulken:BAAALgAECgcJDQAAAA==.Vañquish:BAAALgADCgEJAQAAAA==.',
Ve='Veggyfruit:BAAALgAECgYJEgAAAA==.Ventrois:BAABLgAECn8jAAImAAcJ7x94CgDPAQAmAAcJ7x94CgDPAQAAAA==.Verdarts:BAAALgADCgcJBwAAAA==.Veregas:BAAALgAECgYJEQAAAA==.Vermilion:BAAALgADCgYJCwAAAA==.Vesseven:BAACLgAFFH8HAAIgAAMJ4RUfEAAFAQAgAAMJ4RUfEAAFAQAuAAQKfx4AAiAACAlXHvoXAIwCACAACAlXHvoXAIwCAAAA.',
Vi='Vilienar:BAAALgAECgIJAgAAAA==.Vimao:BAAALgADCgUJCQAAAA==.Vizzy:BAAALgADCgcJBwAAAA==.',
Vo='Voidalic:BAACLgAFFH8QAAIMAAUJVh2QBgC6AQAMAAUJVh2QBgC6AQAuAAQKfxcAAgwACAkJIzcUAN8CAAwACAkJIzcUAN8CAAAA.Voidrend:BAACLgAFFH8QAAMMAAYJExLABgCHAQAMAAUJExLABgCHAQAXAAEJAAD/BQA2AAAuAAQKfykAAgwACQlbIR4JAD8DAAwACQlbIR4JAD8DAAAA.Voimasta:BAAALgADCgIJAgAAAA==.',
Vu='Vuloolu:BAAALgAECgcJEwAAAA==.Vulpiena:BAAALgADCgcJBwAAAA==.Vulvaenjoyer:BAAALgAECgYJBgAAAA==.',
['Vî']='Vî:BAAALgAECgcJDQAAAA==.Vîews:BAAALgAECggJEwAAAA==.',
['Vø']='Vøgue:BAABLgAECn8nAAIOAAkJARQlAgASAgAOAAkJARQlAgASAgAAAA==.',
Wa='Warbidet:BAAALgAECgEJAgAAAA==.Warlockwally:BAAALgAECgQJBwAAAA==.Warloko:BAAALgAECgcJDgAAAA==.Warmason:BAABLgAECn8kAAIWAAgJehSECgCCAQAWAAgJehSECgCCAQAAAA==.Warpheal:BAAALgADCgkJCgAAAA==.Warrida:BAAALgADCgEJAQAAAA==.Washed:BAABLgAECn8YAAMVAAgJCxJtLgBzAQAVAAcJcBRtLgBzAQAcAAQJzgpCRQCgAAAAAA==.',
We='Wealthy:BAABLgAECn8jAAMeAAgJ9xrYBwAeAgAeAAgJnBfYBwAeAgAfAAYJOBf/LgCHAQAAAA==.Wearkit:BAAALgADCgQJBAAAAA==.Weßall:BAAALgADCgcJBwAAAA==.',
Wh='Whiskeydix:BAAALgADCgYJBgAAAA==.Whyisitdark:BAAALgADCgUJBQAAAA==.',
Wi='Wiiska:BAAALgAECgYJBgAAAA==.Wildassassjd:BAAALgADCgUJBQABLgAECgYJBwAPAAAAAA==.',
Wo='Wonderful:BAAALgADCgMJAwAAAA==.',
Wr='Wrakk:BAABLgAECn8gAAINAAgJdBPLCADgAQANAAgJdBPLCADgAQAAAA==.Wrred:BAAALgAECgQJCgAAAA==.',
Xo='Xombi:BAAALgADCgQJBAABLgAECgYJCAAPAAAAAA==.',
Xt='Xtik:BAAALgADCgUJBQAAAA==.',
Yb='Ybeavg:BAAALgADCggJCAAAAA==.',
Yd='Ydduss:BAAALgAECgMJAwABLgAECgkJJwAQAAofAA==.',
Ye='Yeahbuddy:BAAALgADCgQJBAAAAA==.',
Yu='Yunai:BAAALgAECgEJAQAAAA==.',
Ze='Zemi:BAABLgAECn8nAAIlAAkJ9RRkAwAVAgAlAAkJ9RRkAwAVAgAAAA==.Zeneragor:BAAALgAECgQJBAAAAA==.Zenethrius:BAAALgADCgMJAwAAAA==.Zevalia:BAABLgAECn8YAAMkAAYJBh3zJwB1AQAkAAUJfxvzJwB1AQAZAAYJCgu7IQD2AAAAAA==.Zevarya:BAAALgADCgEJAQABLgAECgYJGAAkAAYdAA==.Zevelyon:BAAALgADCgEJAQABLgAECgYJGAAkAAYdAA==.',
Zo='Zophia:BAAALgAECgEJAQAAAA==.Zorak:BAAALgAECgIJAgABLgAFFAMJCgAdAPkeAA==.',
Zt='Ztoned:BAAALgADCgUJBgAAAA==.',
Zu='Zubby:BAABLgAECn8XAAIVAAYJZCA+XwCrAQAVAAYJZCA+XwCrAQAAAA==.Zuddy:BAAALgADCgUJBQAAAA==.Zugrotic:BAAALgAECgYJCQAAAA==.Zugtrek:BAAALgADCgEJAQAAAA==.Zulakunda:BAAALgAECgYJEwAAAA==.Zummey:BAAALgADCgcJBAAAAA==.',
Zy='Zylox:BAAALgAECggJEwAAAA==.',
['Zë']='Zëüs:BAAALgAECgYJEwAAAA==.',
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
