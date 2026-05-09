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

local lookup = {'Mage-Frost','DeathKnight-Unholy','Druid-Restoration','DeathKnight-Frost','Hunter-BeastMastery','Hunter-Marksmanship','Evoker-Preservation','Paladin-Retribution','Druid-Feral','Hunter-Survival','Priest-Shadow','DemonHunter-Devourer','Rogue-Subtlety','Rogue-Assassination','Unknown-Unknown','Mage-Fire','Evoker-Augmentation','Evoker-Devastation','Paladin-Protection','Warlock-Affliction','Warlock-Demonology','Warrior-Protection','DemonHunter-Vengeance','DeathKnight-Blood','Monk-Brewmaster','Druid-Balance','Mage-Arcane','Warlock-Destruction','Paladin-Holy','Priest-Discipline','Priest-Holy','Shaman-Enhancement','Shaman-Elemental','Warrior-Fury','Shaman-Restoration','DemonHunter-Havoc','Monk-Mistweaver','Monk-Windwalker','Warrior-Arms','Druid-Guardian',}
local provider = {region='US',realm='Firetree',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abacabb:BAAALgAECgQJBgAAAA==.',
Ac='Acanthiex:BAAALgADCgQJBAAAAA==.',
Ad='Adnarimn:BAAALgAECgEJAQAAAA==.Adondias:BAABLgAECn8qAAIBAAkJUyMsBAA3AwABAAkJUyMsBAA3AwAAAA==.',
Ae='Aelanthus:BAAALgADCgEJAQAAAA==.Aelinn:BAAALgADCgEJAQAAAA==.',
Ag='Agrevail:BAAALgAECgYJEwAAAA==.',
Ai='Aidendk:BAABLgAECn8cAAICAAkJIR/LJACqAgACAAkJIR/LJACqAgAAAA==.',
Ak='Akrib:BAAALgADCgUJBQAAAA==.Akryllic:BAABLgAECn8lAAIDAAgJTx3eDAB/AgADAAgJTx3eDAB/AgAAAA==.',
Al='Aldari:BAACLgAFFH8OAAIBAAUJvRqVHgBsAQABAAUJvRqVHgBsAQAuAAQKfx0AAgEACQndJO4HAIoDAAEACQndJO4HAIoDAAAA.Allen:BAAALgADCgcJBwAAAA==.Allydk:BAABLgAECn8wAAMCAAkJ2COTAwAwAwACAAkJ2COTAwAwAwAEAAQJhxz9CQD3AAAAAA==.Altrag:BAABLgAECn8yAAMFAAkJWSKjAgAcAwAFAAkJWSKjAgAcAwAGAAEJmAHqmQAaAAAAAA==.Aluc:BAABLgAECn8rAAIHAAkJiQ4uCwCcAQAHAAkJiQ4uCwCcAQAAAA==.Alyrssa:BAAALgAECgYJBgAAAA==.',
An='Andilar:BAABLgAECn8ZAAIIAAgJ/Rg9RgARAgAIAAgJ/Rg9RgARAgAAAA==.Andrepov:BAAALgAECgEJBgAAAA==.Anehii:BAABLgAECn8lAAIJAAgJWgrMDABLAQAJAAgJWgrMDABLAQAAAA==.Aniia:BAAALgAECgYJEwAAAA==.Animaldude:BAACLgAFFH8FAAIKAAIJ/BA2FQCqAAAKAAIJ/BA2FQCqAAAuAAQKfy8AAwoACQmJHykFALwCAAoACQmJHykFALwCAAYAAQneBGyQACoAAAAA.Anjera:BAABLgAECn8WAAILAAcJ4hKUHgBIAQALAAcJ4hKUHgBIAQAAAA==.Anotherdrood:BAAALgAECgcJBwAAAA==.Anslayer:BAAALgAECgEJAQAAAA==.Anwala:BAAALgADCgEJAQAAAA==.Anémie:BAAALgADCgkJDwAAAA==.',
Ap='Apexis:BAABLgAECn8aAAIMAAYJ9RGUUgACAQAMAAYJ9RGUUgACAQAAAA==.Apolion:BAAALgAECgMJBAAAAA==.',
Ar='Arche:BAAALgADCgEJAQAAAA==.Arctodus:BAAALgAECgYJCgAAAA==.Arghuul:BAABLgAECn8pAAMNAAkJEh1yBwAZAwANAAkJEh1yBwAZAwAOAAEJ4RukGgBTAAAAAA==.Arks:BAABLgAECn8eAAIDAAgJPxuXDwBbAgADAAgJPxuXDwBbAgAAAA==.Arksmash:BAAALgADCgcJBwAAAA==.',
As='Asperges:BAAALgAFFAEJAQAAAA==.Astropâ:BAAALgAECgEJAQAAAA==.',
Ax='Axsisdknight:BAAALgAECgEJAQAAAA==.',
Az='Azasei:BAAALgADCgMJBAAAAA==.Azathoth:BAAALgADCgUJBwABLgAECgMJAwAPAAAAAA==.',
['Aë']='Aëlana:BAABLgAECn8pAAIBAAkJuxo2HABBAgABAAkJuxo2HABBAgAAAA==.',
Ba='Babybowser:BAAALgADCgEJAQAAAA==.Baconn:BAACLgAFFH8PAAIIAAQJsxuWCQBhAQAIAAQJsxuWCQBhAQAuAAQKfx4AAggABwnuJCAfALECAAgABwnuJCAfALECAAAA.Badbunny:BAAALgAECgUJEgAAAA==.Bailey:BAAALgADCgYJCQAAAA==.Baileyc:BAAALgAECgQJBAAAAA==.Balkhan:BAAALgADCgMJAwAAAA==.Balun:BAAALgAECgEJAwAAAA==.Banza:BAAALgAECgIJAgAAAA==.Barsh:BAABLgAECn8ZAAIMAAYJ1xnQTADBAQAMAAYJ1xnQTADBAQABLgAECgkJLQAQAC4fAA==.Bashful:BAAALgAECgEJAQAAAA==.Battlebidet:BAAALgAECgEJAgAAAA==.',
Be='Beauregarde:BAAALgADCggJBgAAAA==.Beef:BAACLgAFFH8OAAIRAAUJtxysCABjAQARAAUJtxysCABjAQAuAAQKfxoAAxEACAkHJvUFACQDABEACAl4I/UFACQDABIABAlBJREUAKUBAAAA.Beefdido:BAABLgAECn8cAAIOAAgJ9RR6BADKAQAOAAgJ9RR6BADKAQAAAA==.Beefstew:BAAALgAECgMJAwAAAA==.Befouled:BAAALgAECgcJEQAAAA==.Belinos:BAAALgADCgEJAQAAAA==.Belithe:BAABLgAECn8aAAITAAYJ8gV6IgCCAAATAAYJ8gV6IgCCAAAAAA==.Benson:BAAALgADCgIJAgAAAA==.Berrymanalow:BAACLgAFFH8JAAIBAAMJcQp0UADhAAABAAMJcQp0UADhAAAuAAQKfyYAAgEACAk1FUoxANsBAAEACAk1FUoxANsBAAAA.',
Bi='Bigpapapumpz:BAAALgAECgYJBwAAAA==.Bijtoo:BAABLgAECn8oAAMUAAgJORxMAgAMAgAUAAgJORxMAgAMAgAVAAUJXg0bcADqAAAAAA==.Bikkels:BAAALgADCgYJDQABLgAECgUJBQAPAAAAAA==.Bingsoo:BAABLgAECn8nAAIBAAkJLhjWGgBJAgABAAkJLhjWGgBJAgAAAA==.Bist:BAAALgAECgUJBwABLgAECgcJHwAIAI0lAA==.Bistopher:BAABLgAECn8fAAIIAAcJjSUDFADzAgAIAAcJjSUDFADzAgAAAA==.Bisty:BAAALgADCgYJCgABLgAECgcJHwAIAI0lAA==.',
Bj='Bjorney:BAABLgAECn8dAAILAAgJ3hGgEgCyAQALAAgJ3hGgEgCyAQAAAA==.',
Bl='Blankspace:BAAALgAECgUJCgAAAA==.Blaserr:BAABLgAECn8WAAIWAAgJvBbLFQCxAQAWAAgJvBbLFQCxAQAAAA==.Blessurface:BAAALgAECgMJAwAAAA==.Blindfire:BAABLgAECn8hAAIBAAkJ8x1iHAAFAwABAAkJ8x1iHAAFAwAAAA==.Blindspirit:BAAALgAECgYJDQAAAA==.Blindvngence:BAABLgAECn8kAAMXAAkJDxWfCADuAQAXAAgJ8BafCADuAQAMAAUJqwoEbgC/AAAAAA==.Blizzerker:BAAALgAECgEJAQAAAA==.Bloodrayne:BAAALgAECgIJAgAAAA==.Bludoosh:BAAALgAECgYJDQAAAA==.Blumken:BAAALgADCgEJAQAAAA==.',
Bo='Bombpops:BAAALgADCgEJAQABLgAECgEJAQAPAAAAAA==.Bonkdeath:BAABLgAECn8bAAMCAAgJiAqmVAA/AQACAAcJgAqmVAA/AQAYAAEJtQoeOwAoAAAAAA==.Boomskii:BAAALgADCgIJAgAAAA==.Boomymonk:BAABLgAECn8ZAAIZAAcJsR8xFABuAgAZAAcJsR8xFABuAgAAAA==.Boss:BAABLgAFFH8IAAICAAQJjSFOGQByAQACAAQJjSFOGQByAQABLgAFFAcJFAAaAOkaAA==.Bourius:BAAALgAECgUJBgABLgAFFAQJBgAIACgIAA==.Bowzette:BAAALgAECgQJBAAAAA==.',
Br='Br:BAABLgAECn8hAAIDAAkJ0SGyBgDlAgADAAkJ0SGyBgDlAgAAAA==.Brauxx:BAAALgADCgcJCQAAAA==.Breadermonk:BAABLgAECn8ZAAIZAAgJ0CUnAgD1AgAZAAgJ0CUnAgD1AgAAAA==.Brezanyou:BAABLgAECn8gAAIDAAYJoAr2SgDnAAADAAYJoAr2SgDnAAABLgAECgcJDQAPAAAAAA==.Broblowa:BAAALgADCgEJAQAAAA==.Broly:BAAALgADCgcJDAABLgAECgMJAwAPAAAAAA==.Brotherblud:BAAALgADCgkJCgAAAA==.Brøx:BAABLgAECn8pAAICAAgJsh0aEwBjAgACAAgJsh0aEwBjAgAAAA==.',
Bu='Bubbelhearth:BAAALgAECgYJDAAAAA==.Budyzer:BAAALgAECgMJAwAAAA==.Builtdif:BAAALgADCgYJBgABLgAECggJLAAIADYkAA==.Bumbaclottx:BAAALgAECgMJBAAAAA==.Bunnyboy:BAAALgAECgQJCgAAAA==.Burlen:BAABLgAECn8aAAMBAAgJuRvHRwBgAgABAAgJuRvHRwBgAgAbAAQJxBpnDQDyAAAAAA==.Bustarime:BAAALgADCgkJLgAAAA==.Buyagram:BAAALgADCgIJAQAAAA==.',
Bw='Bwonsamdeez:BAAALgADCgYJBgAAAA==.',
['Bî']='Bîrth:BAACLgAFFH8FAAIBAAIJOQ1WYQClAAABAAIJOQ1WYQClAAAuAAQKfyYAAgEACQkDIBEgACsCAAEACQkDIBEgACsCAAAA.',
Ca='Caeleste:BAAALgAECgcJDAAAAA==.Calic:BAABLgAECn8tAAMcAAkJqxtoBgBpAgAcAAgJzhxoBgBpAgAVAAkJshZ4FAA+AgAAAA==.Calryuu:BAABLgAECn8fAAIZAAgJmR2zCQAqAgAZAAgJmR2zCQAqAgAAAA==.Caltrask:BAAALgAECgIJAgAAAA==.Cambiön:BAACLgAFFH8FAAIBAAMJxgdMUQDeAAABAAMJxgdMUQDeAAAuAAQKfyYAAgEACAkWG/AfACsCAAEACAkWG/AfACsCAAAA.Cameltoetem:BAAALgAECgQJAwAAAA==.Canape:BAABLgAECn8ZAAIdAAYJHBsgIACGAQAdAAYJHBsgIACGAQAAAA==.Capnmurlock:BAAALgADCgEJAQAAAA==.Captnmurzzp:BAAALgADCgkJDgAAAA==.Carpetcrumbs:BAAALgAECgEJAQAAAA==.Castasaurus:BAAALgAECgQJBAAAAA==.Catharsis:BAACLgAFFH8UAAMeAAcJziDVAwApAgAeAAcJhCDVAwApAgAfAAEJHCUnEQBiAAAuAAQKfyEABB4ACQn5JSEAAOkDAB4ACQn5JSEAAOkDAB8ABwlYJQUKAKwCAAsAAQmRGkxJAE0AAAAA.',
Ce='Ceer:BAAALgADCggJDQAAAA==.Cenno:BAABLgAECn8tAAICAAkJvxUmHgAUAgACAAkJvxUmHgAUAgAAAA==.Cerioth:BAAALgAECgQJBAAAAA==.',
Ch='Chantyu:BAAALgADCgUJCAABLgAECgcJDQAPAAAAAA==.Charlixcx:BAAALgADCgEJAQAAAA==.Chickenman:BAAALgAECgcJDgAAAA==.Chickienuggs:BAAALgADCgcJCgAAAA==.Chiflado:BAAALgAECgcJCwAAAA==.Chillinda:BAAALgAECgIJBQAAAA==.Chillpoppin:BAABLgAECn8ZAAMgAAgJCyKlAQC2AgAgAAgJCyKlAQC2AgAhAAIJ9BbTcgB3AAAAAA==.Chinpokomon:BAAALgAECgkJOgAAAQ==.Chompsy:BAABLgAECn8dAAIBAAgJrxm0QQBzAgABAAgJrxm0QQBzAgABLgAFFAQJCAAIAHIQAA==.Chubbychi:BAAALgAECgEJAgABLgAECgcJDQAPAAAAAA==.',
Ci='Ciei:BAAALgAECgMJBAAAAA==.Cilya:BAAALgAECgYJCAAAAA==.Citrusghoul:BAAALgAECgYJDQAAAA==.Citruslite:BAAALgAECgEJAQAAAA==.',
Cl='Clockworkx:BAAALgAECgEJAQAAAA==.',
Co='Cole:BAABLgAECn8jAAMWAAgJyx/+BwD+AQAWAAgJbxj+BwD+AQAiAAYJ9iDyGwCIAQAAAA==.Conceptheals:BAAALgAECgYJEgAAAA==.Confessia:BAAALgAECgYJCgAAAA==.Constantine:BAAALgAECgIJAwAAAA==.Costcobeef:BAAALgAECgEJAQABLgAECgIJAgAPAAAAAA==.Couchlocked:BAAALgADCgEJAQAAAA==.',
Cr='Crackle:BAAALgAECgQJBwAAAA==.Criticalmiss:BAAALgAECgQJBwABLgAFFAUJFgACAJsdAA==.Critsae:BAACLgAFFH8OAAICAAUJHRmMDwBjAQACAAUJHRmMDwBjAQAuAAQKfx8AAgIACAk2IFkWAPYCAAIACAk2IFkWAPYCAAAA.Critydarkirn:BAACLgAFFH8FAAIdAAMJ/x5pFAANAQAdAAMJ/x5pFAANAQAuAAQKfyoABB0ACQkZHuMcAC8CAB0ACQkZHuMcAC8CAAgABQn2EdVXAEIBABMABQn4FT0TABABAAAA.Crypticdh:BAABLgAECn8TAAMMAAYJERYZQAA5AQAMAAYJERYZQAA5AQAXAAEJAAB5JgAAAAAAAA==.Cryptø:BAAALgAECgYJBwAAAA==.',
Cv='Cvrcvss:BAABLgAECn8ZAAQVAAgJGhNPYQCmAQAVAAcJlRNPYQCmAQAcAAUJhg4WKQAeAQAUAAEJAABrLgBBAAAAAA==.',
Cy='Cybele:BAABLgAECn8lAAIMAAgJvSD9CwBvAgAMAAgJvSD9CwBvAgAAAA==.Cypriss:BAAALgAECgIJBAAAAA==.',
['Cë']='Cëlestial:BAAALgAECgYJBwAAAA==.',
Da='Dabadjuju:BAAALgAECgUJDQAAAA==.Dagoonfather:BAAALgAECggJEwAAAA==.Dale:BAAALgADCgMJAwAAAA==.Dandorllan:BAACLgAFFH8LAAIdAAMJ8x4mGADiAAAdAAMJ8x4mGADiAAAuAAQKfycAAx0ACQkHIz8BAHgDAB0ACQkHIz8BAHgDAAgACQkyJTEBAGUDAAAA.Dandowaz:BAABLgAFFH8HAAIjAAMJLhYkIwDJAAAjAAMJLhYkIwDJAAABLgAFFAMJCwAdAPMeAA==.Dandyrandy:BAABLgAECn8qAAMIAAkJXxU3FwBBAgAIAAkJXxU3FwBBAgAdAAgJJRGrLgDJAQAAAA==.Dani:BAAALgADCgUJCQAAAA==.Dareick:BAAALgAECgQJDAAAAA==.Darthashmire:BAAALgAECgQJBQAAAA==.Darthavenger:BAAALgAECgcJDgAAAA==.Dayday:BAABLgAECn8bAAIaAAgJ0hB9GgBjAQAaAAgJ0hB9GgBjAQAAAA==.Dazzazn:BAABLgAECn8VAAIiAAYJNQH7WgBOAAAiAAYJNQH7WgBOAAAAAA==.',
De='Decious:BAABLgAECn8oAAIIAAkJlBnbEQBsAgAIAAkJlBnbEQBsAgAAAA==.Deepfist:BAABLgAECn8sAAIZAAkJayBSAgDuAgAZAAkJayBSAgDuAgAAAA==.Deepfried:BAAALgAECgMJBQAAAA==.Defjam:BAABLgAECn8iAAIBAAgJjRsAMQDcAQABAAgJjRsAMQDcAQAAAA==.Delath:BAAALgAECgIJAgAAAA==.Deleerious:BAEALgAECgQJBAABLgAFFAUJEQANAMwlAA==.Delicia:BAABLgAECn8aAAMeAAgJqQ9sEwCpAQAeAAgJDQ1sEwCpAQAfAAYJQA9APgBBAQAAAA==.Delicias:BAAALgAECgUJBQABLgAECggJGgAeAKkPAA==.Dellbelphine:BAABLgAECn8wAAIIAAkJ/x38CwCjAgAIAAkJ/x38CwCjAgAAAA==.Deminis:BAAALgADCgYJBgAAAA==.Demonbud:BAAALgAECgYJCgABLgAECggJHQASAAAgAA==.Demoncarlos:BAACLgAFFH8PAAIMAAQJJxsNFABdAQAMAAQJJxsNFABdAQAuAAQKfyQAAgwACQnTHQQeAJ4CAAwACQnTHQQeAJ4CAAAA.Demonicscale:BAACLgAFFH8JAAIVAAMJHwJeUwCnAAAVAAMJHwJeUwCnAAAuAAQKfysAAxUACQkZEjpPANoBABUACQkZEjpPANoBABQAAQlIBc41AC4AAAAA.Demonskii:BAABLgAECn8uAAMkAAgJ0iGYCADZAgAkAAgJ0iGYCADZAgAMAAIJYwyemABgAAAAAA==.Demton:BAABLgAECn8uAAIkAAkJfRu4AwCeAgAkAAkJfRu4AwCeAgAAAA==.Denken:BAABLgAFFH8TAAIhAAcJOxWyAgDwAQAhAAcJOxWyAgDwAQAAAA==.Deuslucis:BAAALgADCgEJAQAAAA==.Dezmage:BAAALgADCgYJBgAAAA==.Dezpriest:BAAALgAECgEJAgAAAA==.',
Di='Diagram:BAAALgAECgUJCAAAAA==.Diatonic:BAAALgADCgQJBAABLgAFFAMJCQAMACweAA==.Dildrathion:BAAALgAECgYJBgAAAA==.Direkau:BAABLgAECn8wAAIWAAkJpCVIAAByAwAWAAkJpCVIAAByAwAAAA==.Dishonesty:BAAALgADCgYJBgAAAA==.Divinity:BAAALgAECgYJBgAAAA==.Diwata:BAACLgAFFH8ZAAIeAAYJthitBAATAgAeAAYJthitBAATAgAuAAQKfyoAAx4ACQngG1UIAFkCAB4ACQnYG1UIAFkCAB8ABgnNDgE+AEIBAAAA.',
Do='Dogler:BAACLgAFFH8IAAMDAAMJISCuFgAZAQADAAMJISCuFgAZAQAaAAEJigMOKgBAAAAuAAQKfx8AAwMACAliJIMLAOQCAAMACAliJIMLAOQCABoABgnIGRQYAHoBAAAA.Dojaz:BAABLgAECn8oAAMMAAkJ4gxnLgB9AQAMAAkJ3QxnLgB9AQAkAAIJqAmxXwBjAAAAAA==.Doki:BAAALgADCgQJBAAAAA==.Domeydome:BAAALgAECgEJAQABLgAECggJGAABADkaAA==.Donthitgary:BAAALgAECgIJAgAAAA==.Dooley:BAABLgAECn8UAAIlAAgJVRgDHgDGAQAlAAgJVRgDHgDGAQAAAA==.Doomgrapple:BAAALgAECgUJBQAAAA==.Doriahn:BAAALgAECgYJDQAAAA==.',
Dr='Draconica:BAABLgAECn8dAAISAAgJACAsAwDwAgASAAgJACAsAwDwAgAAAA==.Dracussy:BAABLgAECn8mAAMRAAkJmxpgCwAVAgARAAkJmxpgCwAVAgASAAIJkA7eNABtAAAAAA==.Dragar:BAABLgAECn8jAAIiAAkJDxeuCwAvAgAiAAkJDxeuCwAvAgAAAA==.Dragonler:BAAALgAECgMJAwABLgAFFAMJCAADACEgAA==.Dragoon:BAAALgAECgYJBgAAAA==.Draktha:BAAALgAECgQJBAABLgAECgcJFwASAFwjAA==.Dreamchaser:BAAALgAECgQJBAAAAA==.Dreddful:BAAALgAECgEJBQAAAA==.Drkelso:BAABLgAECn8oAAIBAAgJ8g2PRACZAQABAAgJ8g2PRACZAQAAAA==.Dropswitch:BAAALgADCgEJAQAAAA==.',
Du='Duchalu:BAABLgAECn8uAAIiAAkJTxOVDQATAgAiAAkJTxOVDQATAgAAAA==.Durtbag:BAAALgADCgQJBwAAAA==.',
Dw='Dwarrfie:BAAALgAECgUJBgAAAA==.',
Dy='Dynabear:BAAALgADCgQJCQAAAA==.',
['Dè']='Dèz:BAABLgAECn8eAAMMAAgJeBpyJwCeAQAMAAgJeBpyJwCeAQAXAAMJmg/kHgCQAAAAAA==.',
['Dú']='Dúncan:BAAALgAECgYJBgAAAA==.',
Ei='Eione:BAABLgAECn8pAAIaAAgJABhQEADOAQAaAAgJABhQEADOAQAAAA==.',
El='Elaswyn:BAAALgAECgQJBwAAAA==.Elemantary:BAAALgAECgcJCAAAAA==.Elfieras:BAAALgAECgIJAgABLgAECgYJBwAPAAAAAA==.Elfies:BAAALgADCgYJBwAAAA==.Elinez:BAAALgAECgEJAQAAAA==.Ellcrys:BAABLgAECn8fAAIcAAgJgA1mFwCOAQAcAAgJgA1mFwCOAQAAAA==.Elvinshiznic:BAAALgAECggJDgAAAA==.Elyzah:BAABLgAECn8cAAMVAAgJLRovHAAHAgAVAAgJLRovHAAHAgAcAAEJXgjzdQAvAAAAAA==.',
Em='Emagine:BAABLgAECn8sAAIjAAkJQCPGAQBXAwAjAAkJQCPGAQBXAwAAAA==.Emeraldbeast:BAACLgAFFH8SAAIDAAUJfxNyDQBwAQADAAUJfxNyDQBwAQAuAAQKfyEAAwMACAkJHWUaAGcCAAMACAkJHWUaAGcCABoAAgleEnBBAHoAAAAA.',
En='Enni:BAACLgAFFH8JAAIMAAMJXxwsKAARAQAMAAMJXxwsKAARAQAuAAQKfyIAAgwACQnIIAgQAP4CAAwACQnIIAgQAP4CAAAA.',
Er='Erengarde:BAABLgAECn8eAAIdAAgJAxsVFwBZAgAdAAgJAxsVFwBZAgAAAA==.Eri:BAAALgAECgQJCgAAAA==.Erissra:BAABLgAECn8ZAAMUAAkJAgxWBwDfAQAUAAgJ4wxWBwDfAQAVAAYJygX2swDxAAAAAA==.Eroeda:BAABLgAECn8gAAIkAAgJrQ+6EQBsAQAkAAgJrQ+6EQBsAQAAAA==.',
Es='Escanør:BAAALgAECgQJBQABLgAECgcJDgAPAAAAAA==.',
Ev='Evvy:BAAALgADCgcJCQAAAA==.',
Ex='Exil:BAAALgADCgcJCgAAAA==.Exo:BAABLgAECn8wAAIDAAkJLSQZAgBrAwADAAkJLSQZAgBrAwAAAA==.Exosham:BAAALgADCgMJAwABLgAECgkJMAADAC0kAA==.',
Ey='Eynya:BAAALgADCgcJBwABLgAECgQJCAAPAAAAAA==.',
Ez='Ezfrost:BAAALgAFFAEJAgAAAA==.Ezsmash:BAACLgAFFH8HAAIiAAMJ7B7IFAALAQAiAAMJ7B7IFAALAQAuAAQKfxgAAiIABwmxHf8hAEQCACIABwmxHf8hAEQCAAAA.',
['Eñ']='Eñkei:BAAALgAECgEJAQAAAA==.',
Fa='Faeline:BAAALgAECgMJBgAAAA==.Falkichu:BAAALgADCgUJBQAAAA==.Familiarface:BAAALgAECgYJDQAAAA==.Fastfeet:BAABLgAFFH8NAAIDAAUJtBTcCwCEAQADAAUJtBTcCwCEAQAAAA==.',
Fe='Felam:BAAALgADCgcJBwAAAA==.Ferachio:BAAALgAECgQJBQAAAA==.',
Ff='Ffreshcope:BAABLgAFFH8FAAICAAIJyxX3ZgCrAAACAAIJyxX3ZgCrAAABLgAFFAUJDQAUAOwZAA==.',
Fi='Fierysquish:BAAALgADCgUJBgAAAA==.Fightinmoose:BAAALgAECgQJCAAAAA==.Finzak:BAAALgAECgEJAQAAAA==.Fireblitzer:BAAALgAECgMJBAAAAA==.Fistferge:BAAALgAECggJEAABLgAECgcJGQATABkgAA==.',
Fn='Fnaskmar:BAABLgAECn8ZAAIFAAgJFSHsCAClAgAFAAgJFSHsCAClAgAAAA==.',
Fo='Fogpaw:BAAALgADCgkJGAAAAA==.Foosaa:BAAALgAECgcJDgAAAA==.Forbearance:BAABLgAECn8wAAITAAkJsyNsAAA1AwATAAkJsyNsAAA1AwAAAA==.',
Fr='Franco:BAABLgAECn8aAAIFAAkJEQxxMACMAQAFAAkJEQxxMACMAQAAAA==.Freshfresh:BAAALgAECgUJBgABLgAFFAUJDQAUAOwZAA==.Freshlock:BAACLgAFFH8NAAQUAAUJ7BktBAB1AAAVAAIJlBk+NACqAAAUAAIJ/iYtBAB1AAAcAAIJYRUPEwBZAAAuAAQKfxkABBwACQkxIkQMAP4BABwABQlcJUQMAP4BABUABgkzH2hOAN0BABQABAk/JL8JAKYBAAAA.Frickvicious:BAAALgADCgIJAgAAAA==.Friend:BAAALgAECgEJAgAAAA==.Fright:BAABLgAECn8bAAIIAAgJLBktQwB8AQAIAAgJLBktQwB8AQAAAA==.Friska:BAAALgAECgUJCAAAAA==.Frostbolt:BAAALgAECgEJAQAAAA==.Frostcool:BAABLgAECn8YAAIBAAgJwgxCRwCRAQABAAgJwgxCRwCRAQAAAA==.Frostyh:BAAALgAECgYJCQAAAA==.Frostyp:BAACLgAFFH8NAAILAAQJNQqODQAzAQALAAQJNQqODQAzAQAuAAQKfyAAAgsACQmeGSoOAKACAAsACQmeGSoOAKACAAAA.',
Fu='Furion:BAABLgAECn8UAAIiAAYJjRTwTAByAQAiAAYJjRTwTAByAQAAAA==.Furiousbruja:BAAALgAECgYJDwAAAA==.Furiousnun:BAAALgADCgYJBwAAAA==.Furtivis:BAAALgAECgMJAwAAAA==.',
Fy='Fyre:BAAALgAECggJDgAAAA==.Fyrebird:BAAALgAECgQJBQABLgAECggJDgAPAAAAAA==.',
Ga='Galadhriel:BAABLgAECn8sAAMDAAkJjxuHEABQAgADAAkJjxuHEABQAgAaAAEJVgNAjQAhAAAAAA==.Galadima:BAACLgAFFH8IAAIdAAQJDRegDwA5AQAdAAQJDRegDwA5AQAuAAQKfygAAh0ACAnkHCEKAG8CAB0ACAnkHCEKAG8CAAAA.Galaxywing:BAAALgAECgYJDAAAAA==.Ganador:BAABLgAECn8oAAQVAAkJ6RqhFQA1AgAVAAcJExuhFQA1AgAcAAQJiRPeMAD2AAAUAAEJSxRAFgBAAAAAAA==.Gayguyender:BAAALgAECgUJDQAAAA==.Gazzerfroz:BAAALgAECgEJAQAAAA==.',
Gb='Gbones:BAAALgAECgEJAwABLgAECgQJCAAPAAAAAA==.',
Ge='Geerah:BAAALgADCgYJBgAAAA==.Gennoro:BAAALgADCgcJBwABLgAECggJGQAgAAsiAA==.',
Gi='Givesburger:BAAALgAECgEJAQAAAA==.',
Gl='Glizzies:BAABLgAECn8sAAIIAAgJNiSlCwAxAwAIAAgJNiSlCwAxAwAAAA==.Glocky:BAAALgADCgcJBwAAAA==.',
Gn='Gnomeofdeath:BAABLgAECn8cAAICAAkJKSHbFgDyAgACAAkJKSHbFgDyAgAAAA==.',
Go='Gokusan:BAAALgADCgYJBwABLgAECggJIQAVAHYhAA==.Gomgar:BAAALgADCgcJFwAAAA==.Gooned:BAABLgAECn8jAAMNAAgJ3RUVDADfAQANAAgJ3RUVDADfAQAOAAEJWAsXHgA9AAAAAA==.Goonforall:BAAALgADCgEJAQAAAA==.',
Gr='Grampus:BAAALgADCgIJAgABLgADCgYJBgAPAAAAAA==.Grashoppa:BAAALgAECgYJDwAAAA==.Greentide:BAACLgAFFH8FAAIjAAIJSg9cMgB8AAAjAAIJSg9cMgB8AAAuAAQKfykAAiMACQlkHqUPAJsCACMACQlkHqUPAJsCAAAA.Grengar:BAAALgAECgYJDgAAAA==.Groovybun:BAAALgADCgIJAgAAAA==.Groovymochi:BAABLgAECn8oAAIlAAgJtQ0xGQCGAQAlAAgJtQ0xGQCGAQAAAA==.',
Gu='Guccimaybe:BAABLgAECn8fAAIgAAgJ+hHSDAD2AQAgAAgJ+hHSDAD2AQAAAA==.Guldaniel:BAAALgADCgEJAQAAAA==.Guldanramsey:BAABLgAECn8VAAMUAAcJ9hgVCQC2AQAUAAYJPR0VCQC2AQAVAAcJ3g+KfABiAQAAAA==.Gunjá:BAAALgADCgYJDgAAAA==.',
Gw='Gwynastrasza:BAAALgAECgQJCQABLgAFFAYJFAABANcXAA==.Gwynneth:BAAALgAECgEJAQABLgAFFAYJFAABANcXAA==.',
Gx='Gxre:BAAALgAECgkJAgAAAA==.',
['Gò']='Gòku:BAABLgAECn8hAAMVAAgJdiFgDQCCAgAVAAcJdiFgDQCCAgAcAAIJvhF3TACIAAAAAA==.',
['Gö']='Göuf:BAAALgAECgcJBwAAAA==.',
['Gü']='Güy:BAAALgAECggJEwAAAA==.',
Ha='Halea:BAABLgAECn8ZAAIMAAgJpRwvIwB/AgAMAAgJpRwvIwB/AgAAAA==.Haleluya:BAAALgAECgYJDQABLgAECggJGQAMAKUcAA==.Halepurr:BAAALgADCgIJAgABLgAECggJGQAMAKUcAA==.Halogenrofl:BAABLgAECn8bAAIkAAgJgxhXCQD3AQAkAAgJgxhXCQD3AQAAAA==.Hammahtime:BAAALgADCgcJBwAAAA==.Hammerferge:BAABLgAECn8ZAAITAAcJGSCgCQA3AgATAAcJGSCgCQA3AgAAAA==.Handsofelune:BAAALgAECgQJCAAAAA==.Hannibol:BAAALgADCgYJCAAAAA==.Happa:BAAALgADCgkJCQABLgAFFAQJBgAgAPYbAA==.Harrowhark:BAAALgAECgUJEwAAAA==.Hawktwua:BAAALgAFFAEJAQAAAA==.Hawtshot:BAAALgAECgQJBgAAAA==.Hazelena:BAAALgADCgkJFgAAAA==.',
Hb='Hbz:BAABLgAECn8uAAIWAAkJsh04AwCbAgAWAAkJsh04AwCbAgAAAA==.',
He='Healingbrew:BAACLgAFFH8HAAIZAAMJgxerHADzAAAZAAMJgxerHADzAAAuAAQKfx4AAhkACAk7HOAWAFECABkACAk7HOAWAFECAAAA.Healzplz:BAAALgADCgcJBwAAAA==.Herekittycat:BAAALgAECgEJAQAAAA==.Heretoohelp:BAAALgAECgYJEAAAAA==.',
Hi='Hildar:BAABLgAECn8aAAIdAAcJRBUNHACoAQAdAAcJRBUNHACoAQAAAA==.Hillcoast:BAAALgADCgUJBQAAAA==.',
Ho='Holeymoley:BAAALgAECgEJAgAAAA==.Holibeef:BAAALgAECgcJDQAAAA==.Holybits:BAABLgAECn8YAAIdAAgJeRGsJgBVAQAdAAgJeRGsJgBVAQAAAA==.Holylinoleum:BAAALgADCgQJBAABLgADCggJBgAPAAAAAA==.Holysquish:BAACLgAFFH8TAAIIAAUJARKSFABVAQAIAAUJARKSFABVAQAuAAQKfyUAAggACQm4HjAeALYCAAgACQm4HjAeALYCAAAA.Holyz:BAABLgAECn8gAAILAAgJ6ByaFgAyAgALAAgJ6ByaFgAyAgAAAA==.Homoglobin:BAABLgAFFH8HAAIYAAMJ7QxPFAC2AAAYAAMJ7QxPFAC2AAAAAA==.Honeydip:BAABLgAECn8wAAIFAAkJChoyDgBoAgAFAAkJChoyDgBoAgAAAA==.Honésty:BAABLgAECn8kAAIfAAcJNRmuGgAHAgAfAAcJNRmuGgAHAgAAAA==.Hoontertile:BAAALgADCgcJBwAAAA==.Horsegirl:BAAALgAECgEJAQAAAA==.Hotfistbaby:BAAALgAECgcJCgAAAA==.Hotspankyboi:BAABLgAECn8UAAITAAgJRSbxAABjAwATAAgJRSbxAABjAwAAAA==.',
Hr='Hruun:BAAALgADCgcJBwAAAA==.',
Hu='Huntskii:BAAALgAECgQJBgAAAA==.Hussle:BAAALgADCggJDgAAAA==.',
Hw='Hwaryeong:BAAALgADCgEJAQAAAA==.',
Ic='Iceicebabye:BAAALgAECgQJCQAAAA==.Iceleaf:BAAALgADCgYJBQAAAA==.Iciest:BAAALgAECgMJAgABLgAECggJLAAIADYkAA==.',
Ig='Iger:BAAALgADCgcJDwAAAA==.',
Ih='Iha:BAAALgAECgEJAgAAAA==.',
Ij='Ijudgepeople:BAAALgADCggJCAABLgAECgIJAgAPAAAAAA==.',
Ik='Ikkaroas:BAAALgAECgUJBQAAAA==.Ikkis:BAAALgAECgUJCgAAAA==.Ikmoti:BAAALgAECgEJAQAAAA==.',
Il='Ileinaa:BAABLgAECn85AAIfAAkJGhX2EQDSAQAfAAkJGhX2EQDSAQAAAA==.Iliketrains:BAABLgAECn8rAAIhAAkJgB0YBAC+AgAhAAkJgB0YBAC+AgAAAA==.Illuminatì:BAAALgAECgcJEAAAAA==.Ilovegrizzly:BAAALgAECgIJAwABLgAECgcJBwAPAAAAAA==.',
Im='Immortalhulk:BAAALgADCgIJAgAAAA==.',
In='Indicud:BAAALgAECgUJCwAAAA==.Inoxiakek:BAAALgAECgQJCQAAAA==.Intensedh:BAAALgAECgYJEwABLgAECggJFgAjAE4bAA==.Intensevok:BAAALgADCgcJBwABLgAECggJFgAjAE4bAA==.Intensifiedx:BAABLgAECn8WAAIjAAgJThsPHgArAgAjAAgJThsPHgArAgAAAA==.',
Ir='Ironwil:BAAALgAECgUJCQAAAA==.',
Is='Iscreamalot:BAABLgAECn8fAAIiAAgJAhkBGQCDAgAiAAgJAhkBGQCDAgAAAA==.Isele:BAAALgAECgQJBAABLgAECgYJCgAPAAAAAA==.',
It='Itybity:BAAALgAECgYJCwAAAA==.',
Iy='Iyatsuki:BAAALgAFFAIJAwAAAA==.',
Ja='Jawbone:BAAALgADCgEJAQAAAA==.Jayfizzle:BAAALgAECgEJAgAAAA==.Jaymazing:BAABLgAECn8aAAIMAAkJ7CE+CgCFAgAMAAkJ7CE+CgCFAgABLgAECgEJAgAPAAAAAA==.',
Ji='Jimmyboy:BAAALgADCgUJBQAAAA==.',
Jo='Joenormousgg:BAAALgADCgUJBQAAAA==.Johnathan:BAAALgADCgEJAQAAAA==.Johnconner:BAAALgAECgYJDwAAAA==.Jonald:BAAALgAECgQJCAABLgAECggJJAAZAMYXAA==.Jongwoo:BAAALgADCgYJCAAAAA==.Jonthecron:BAABLgAECn8kAAMZAAgJxheMEQC4AQAZAAgJxheMEQC4AQAmAAMJpAoFTwBOAAAAAA==.Joojekabab:BAAALgADCgEJAQAAAA==.Jorkinit:BAAALgAECggJEwAAAA==.Jormot:BAAALgAECgEJAQABLgAECggJDgAPAAAAAA==.Jorok:BAABLgAECn8VAAIhAAkJhBXZHAAqAgAhAAkJhBXZHAAqAgAAAA==.',
Ju='Jubilee:BAABLgAECn8hAAIVAAkJFRnaIwCEAgAVAAkJFRnaIwCEAgAAAA==.Jumannji:BAABLgAECn8hAAIhAAkJsx1sBgB+AgAhAAkJsx1sBgB+AgAAAA==.Jumpingbench:BAABLgAECn8aAAIDAAYJlAxkUwDJAAADAAYJlAxkUwDJAAAAAA==.Jurik:BAAALgADCgUJDgAAAA==.Justadragon:BAAALgADCgMJBAAAAA==.',
Ka='Kabluey:BAAALgADCgEJAQAAAA==.Kalarm:BAAALgADCgYJBgAAAA==.Kallidan:BAABLgAECn8cAAIMAAkJ3hSQHQDYAQAMAAkJ3hSQHQDYAQAAAA==.Kallight:BAAALgAECggJEwAAAA==.Karks:BAACLgAFFH8LAAMiAAUJ2Bg3FwD2AAAiAAQJbxY3FwD2AAAnAAEJEiDeCABjAAAuAAQKfx8AAyIACQmEH3UUAKoCACIACQkCG3UUAKoCACcAAwkRGacfAPEAAAAA.Karsaørlong:BAAALgAECgMJBAAAAA==.Kassabekkaia:BAAALgADCggJDgABLgAECggJGQAIAIgMAA==.Katrois:BAAALgAECgYJBgAAAA==.Kayem:BAAALgAECgQJBAAAAA==.Kazroth:BAAALgADCgcJDQAAAA==.',
Kb='Kbe:BAAALgADCgQJBAAAAA==.',
Ke='Kelewan:BAABLgAECn8uAAMCAAkJjBWHHAAeAgACAAkJjxOHHAAeAgAYAAcJZBaoFgCrAQAAAA==.Kellabrimbor:BAAALgADCgUJBQAAAA==.Kellelor:BAAALgAECgEJAwAAAA==.Kerrigan:BAAALgAECgEJAQABLgAECgYJCAAPAAAAAA==.',
Ki='Killkillkill:BAAALgAECgYJBgAAAA==.Kindassuddy:BAABLgAECn8tAAMQAAkJLh+ZAACOAgABAAgJaCCYKgDIAgAQAAkJzhiZAACOAgAAAA==.Kindled:BAABLgAECn8VAAIBAAgJlxauawD+AQABAAgJlxauawD+AQAAAA==.Kinvardar:BAAALgAECgcJEwAAAA==.Kirbbslav:BAAALgAECgIJAgABLgAFFAYJFQAdAGUbAA==.Kirbislav:BAAALgAFFAEJAQABLgAFFAYJFQAdAGUbAA==.Kirbslav:BAACLgAFFH8VAAIdAAYJZRtbBACbAQAdAAYJZRtbBACbAQAuAAQKfyoAAh0ACQm5I6MEACMDAB0ACQm5I6MEACMDAAAA.Kirbyslav:BAABLgAFFH8GAAIDAAUJdRa3CQCfAQADAAUJdRa3CQCfAQABLgAFFAYJFQAdAGUbAA==.Kirkland:BAAALgAECgIJAgAAAA==.Kirklandbeef:BAAALgAECgIJAgAAAA==.Kits:BAAALgAECgEJAQABLgAECggJFQAIABYPAA==.',
Kn='Kniavez:BAABLgAECn8bAAMnAAkJ4gwDEQA8AQAnAAkJ4gwDEQA8AQAiAAIJRgZcVgBeAAAAAA==.',
Ko='Koranova:BAABLgAECn8UAAILAAgJXBZiDQDzAQALAAgJXBZiDQDzAQAAAA==.Korro:BAABLgAECn8pAAIKAAkJUx25AgC8AgAKAAkJUx25AgC8AgAAAA==.Kostin:BAABLgAECn8fAAIiAAgJ/RdrHgBcAgAiAAgJ/RdrHgBcAgAAAA==.',
Kr='Krak:BAAALgAECgYJEAAAAA==.Krasta:BAAALgAECgMJBgAAAA==.Kratosdh:BAAALgADCgMJBAAAAA==.Krolow:BAACLgAFFH8bAAIiAAYJxRo/AgCuAQAiAAYJxRo/AgCuAQAuAAQKfyQAAxYACAnqG8QKAMEBACIABwlOH6gjADgCABYACAnjF8QKAMEBAAAA.Kruugh:BAABLgAECn8bAAIhAAgJkxOqHQBhAQAhAAgJkxOqHQBhAQAAAA==.',
Ku='Kuler:BAABLgAECn8kAAIiAAgJQiHUFACmAgAiAAgJQiHUFACmAgAAAA==.Kungfushrub:BAABLgAECn8ZAAITAAgJ5hAXEQArAQATAAgJ5hAXEQArAQAAAA==.Kurolizian:BAAALgAECgEJAQAAAA==.Kuulandor:BAABLgAECn8lAAIYAAkJOyGTAwAfAwAYAAkJOyGTAwAfAwAAAA==.',
['Kè']='Kèèn:BAACLgAFFH8LAAIIAAMJIR6KDwAsAQAIAAMJIR6KDwAsAQAuAAQKfxQAAggABgliI3RcAM0BAAgABgliI3RcAM0BAAAA.',
['Ké']='Két:BAABLgAECn8ZAAIDAAgJzxoVJwAaAgADAAgJzxoVJwAaAgABLgAFFAIJAgAPAAAAAA==.',
['Kê']='Kêt:BAAALgAFFAIJAgAAAA==.',
['Kí']='Kítkat:BAABLgAECn8VAAIIAAgJFg9xOwCUAQAIAAgJFg9xOwCUAQAAAA==.',
['Kÿ']='Kÿra:BAAALgAECgEJAQAAAA==.',
Le='Leesin:BAAALgAECgEJAgAAAA==.Levelground:BAAALgAFFAIJAwAAAA==.Lewd:BAAALgAECgMJBAABLgAECggJGQAMAKUcAA==.Leylines:BAAALgADCgcJBwAAAA==.',
Li='Liakä:BAAALgADCgYJBgAAAA==.Lightrampant:BAAALgADCgMJAQAAAA==.Lilmonkey:BAAALgADCgQJBgAAAA==.Limegreen:BAAALgADCgEJAQAAAA==.Liquidsevenz:BAABLgAECn8gAAIgAAcJvBPVCQB8AQAgAAcJvBPVCQB8AQAAAA==.Litlit:BAAALgAECgYJCgAAAA==.',
Lo='Lodoss:BAACLgAFFH8GAAIjAAMJBiFOFAAjAQAjAAMJBiFOFAAjAQAuAAQKfysAAiMACAmsHawKAIICACMACAmsHawKAIICAAAA.Lollipops:BAAALgAECgEJAQAAAA==.Lonah:BAAALgAFFAIJAgABLgAFFAMJBQAIAPgZAA==.Lorienb:BAABLgAECn8lAAMLAAgJkhixDwDUAQALAAgJkhixDwDUAQAeAAIJbRCLSQByAAAAAA==.Lotheran:BAAALgADCgEJAQAAAA==.Lothé:BAAALgAECgQJBAAAAA==.Lotlizar:BAAALgADCgEJAQABLgAECggJGwACAIgKAA==.Lowkydead:BAAALgADCgQJBQAAAA==.',
Lu='Lubelesso:BAAALgADCgkJFgAAAA==.Luckehlock:BAACLgAFFH8LAAIUAAUJlyENAAAIAgAUAAUJlyENAAAIAgAuAAQKfyAAAxQACQlwJAsAAN4DABQACQlwJAsAAN4DABUAAQlvALc0ARIAAAEuAAUUBwkIABEAXxQA.Luckehtwo:BAABLgAFFH8IAAIRAAcJXxSOBQDeAQARAAcJXxSOBQDeAQAAAA==.Luxcn:BAABLgAECn8hAAMFAAgJMBarHwDeAQAFAAgJMBarHwDeAQAGAAEJkgR9LAAlAAAAAA==.',
Ma='Macgibbins:BAABLgAECn8ZAAIKAAgJ+xRLCgA1AgAKAAgJ+xRLCgA1AgAAAA==.Madepure:BAAALgAECgMJAwABLgAECggJLAAIADYkAA==.Magus:BAABLgAECn8XAAMBAAcJpCOcUQBCAgABAAcJpCOcUQBCAgAQAAIJ4xITDABuAAABLgAFFAcJFAAaAOkaAA==.Mahyora:BAAALgAECgEJBQAAAA==.Marsoti:BAAALgAECgQJBAAAAA==.Mats:BAAALgADCgYJBgAAAA==.Mavus:BAABLgAECn8UAAIBAAcJ0B1LZgALAgABAAcJ0B1LZgALAgAAAA==.',
Mc='Mccream:BAAALgAECgMJAwAAAA==.',
Me='Melylen:BAAALgAECgQJCAAAAA==.Mezugyouzug:BAAALgADCgQJBAAAAA==.',
Mi='Milkbolt:BAABLgAECn8ZAAIVAAgJ8hJpNACTAQAVAAgJ8hJpNACTAQAAAA==.Milkcream:BAAALgAECgEJAQAAAA==.Minigolf:BAABLgAECn8iAAQMAAgJsBn1IADCAQAMAAgJ+Bj1IADCAQAkAAUJWRnGMABLAQAXAAEJAAB0JgAAAAAAAA==.Minigun:BAABLgAECn8ZAAIKAAgJSx6jCgD5AQAKAAgJSx6jCgD5AQAAAA==.Minioozy:BAAALgADCgUJBQAAAA==.Minivan:BAAALgADCgQJBAABLgAECggJIgAMALAZAA==.Misawa:BAABLgAECn8VAAIMAAgJJQfnSQAbAQAMAAgJJQfnSQAbAQAAAA==.Mizuboxx:BAABLgAECn8lAAIdAAgJZyN0AwAHAwAdAAgJZyN0AwAHAwAAAA==.',
Mo='Molyver:BAABLgAECn8tAAMmAAkJGBngHQA1AQAmAAcJzhXgHQA1AQAlAAUJYA7UKQD/AAAAAA==.Momak:BAAALgAECgQJBAABLgAECgYJCQAPAAAAAA==.Mommey:BAAALgAECgUJBgAAAA==.Monteloco:BAAALgAECgMJAwAAAA==.Moonfrost:BAAALgADCgYJBwAAAA==.Moonkitty:BAAALgADCgEJAQAAAA==.Moonmane:BAABLgAECn8bAAMaAAgJuxlzEADMAQAaAAgJDRhzEADMAQAoAAYJIhh3CwBcAQAAAA==.Moonmellow:BAAALgAECgcJCQAAAA==.Moosin:BAAALgAECgEJAgAAAA==.Mozgus:BAABLgAECn8jAAIfAAgJNCEUEwBHAgAfAAgJNCEUEwBHAgAAAA==.',
Mu='Munder:BAAALgAECgYJDwAAAA==.Murdurio:BAAALgAECgQJCwAAAA==.Musculate:BAAALgAECgkJEgAAAA==.',
Mx='Mxdi:BAABLgAECn8kAAQDAAkJeSIvAgBnAwADAAkJeSIvAgBnAwAaAAIJHBDLVgA1AAAJAAEJzQ3pNgArAAAAAA==.',
My='Myranda:BAAALgADCgMJAwAAAA==.',
Na='Nazdarok:BAAALgAECgMJBAAAAA==.Nazenoth:BAAALgADCgcJFAAAAA==.Nazgûl:BAABLgAECn8aAAIXAAcJ4B53BQC3AQAXAAcJ4B53BQC3AQAAAA==.',
Ne='Necrofearlia:BAABLgAECn8ZAAQVAAgJwhNQLgCqAQAVAAgJzRBQLgCqAQAUAAQJjBh/DwA3AQAcAAMJqAoSTQCGAAAAAA==.Nensha:BAABLgAECn8VAAImAAYJ7g8UIQAdAQAmAAYJ7g8UIQAdAQAAAA==.Nethys:BAABLgAECn8tAAMLAAkJuR2JAwDAAgALAAkJuR2JAwDAAgAeAAEJnAX+XAAoAAAAAA==.',
Ni='Nick:BAACLgAFFH8UAAIaAAcJ6RrRAABNAgAaAAcJ6RrRAABNAgAuAAQKfygABBoACQkeJFoCAJwDABoACQkeJFoCAJwDACgABgmmIFcIACgCAAMAAQnBCPHHADoAAAAA.Nightxangel:BAAALgADCgcJBwAAAA==.',
No='Noctrimm:BAAALgADCgEJAQAAAA==.Nolyt:BAABLgAECn8hAAICAAcJ3QrHWwAuAQACAAcJ3QrHWwAuAQAAAA==.Nonna:BAABLgAECn8dAAInAAgJkB1qBQCFAgAnAAgJkB1qBQCFAgAAAA==.Noolore:BAACLgAFFH8WAAMCAAUJmx2zFQBNAQACAAQJmx2zFQBNAQAYAAEJAAD+MQAAAAAuAAQKfyYAAgIACQm1IV0XAO8CAAIACQm1IV0XAO8CAAAA.Norandil:BAAALgAECgQJBQAAAA==.Notendela:BAAALgAECgEJAQABLgAECgYJCgAPAAAAAA==.',
Nu='Nuiria:BAAALgADCgUJBQAAAA==.Nurfgun:BAABLgAECn8eAAMFAAgJbSP4CAClAgAFAAgJOiL4CAClAgAGAAYJ/yJAHgA1AgAAAA==.Nurfroll:BAAALgAECggJCgABLgAECggJHgAFAG0jAA==.Nurfstrasza:BAAALgADCgYJBgABLgAECggJHgAFAG0jAA==.',
Nw='Nwahher:BAAALgAECgMJAwAAAA==.',
Of='Offleash:BAAALgAECgcJBgAAAA==.',
Om='Ominous:BAAALgADCgYJBgAAAA==.',
On='Onefelswoop:BAAALgADCgQJBAABLgAECggJGQATAOYQAA==.Onlock:BAAALgADCgYJBgAAAA==.Onlyfrost:BAAALgADCgcJCQAAAA==.Onlyslams:BAABLgAECn8fAAMZAAgJqRwsFwBNAgAZAAgJqRwsFwBNAgAlAAEJzwK/ZQAaAAAAAA==.',
Op='Opheliana:BAAALgADCgEJAQAAAA==.',
Or='Orcsmash:BAAALgAECgUJDwAAAA==.',
Ow='Owlwithahat:BAAALgADCgcJDQAAAA==.',
Ox='Oxen:BAACLgAFFH8HAAICAAMJuQ+5TQD0AAACAAMJuQ+5TQD0AAAuAAQKfygABAIACQmOITwWAEkCABgACQnWHtcJAH4CAAIACAkGHzwWAEkCAAQAAQlvDRYXADQAAAAA.',
Pa='Padraig:BAAALgADCgcJBwAAAA==.Passoot:BAAALgAECgEJBwAAAA==.',
Pe='Pega:BAAALgADCgQJBAABLgAFFAQJBgAgAPYbAA==.Pegah:BAAALgAECgMJAwAAAA==.Pege:BAACLgAFFH8GAAIgAAQJ9hviAQBuAQAgAAQJ9hviAQBuAQAuAAQKfyUAAiAACAlXIj0DAAADACAACAlXIj0DAAADAAAA.Penniee:BAAALgAECgMJBAAAAA==.Penniwing:BAABLgAECn8nAAQRAAkJYxwHHADoAQARAAcJgxoHHADoAQAHAAkJYgsdHgCRAQASAAEJ0hKiQAAvAAAAAA==.Percival:BAECLgAFFH8ZAAIKAAcJ6xovAABOAgAKAAcJ6xovAABOAgAuAAQKfyAABAoACQlcI0AAAMQDAAoACQlcI0AAAMQDAAYABQnNHPZMAB0BAAUAAwmVI/GdAJQAAAAA.',
Ph='Phaedra:BAAALgAECgkJOgAAAQ==.Phanuel:BAABLgAECn8VAAIBAAYJSQ31zABQAQABAAYJSQ31zABQAQABLgAFFAMJCwAIACEeAA==.Phealvoker:BAAALgADCgIJAgABLgAECggJKAAhAEgfAA==.',
Pi='Piffboy:BAABLgAECn8eAAMIAAgJMRQHOQCcAQAIAAgJMRQHOQCcAQAdAAMJ+geMRQCXAAAAAA==.Pillargodx:BAAALgAECgEJAQAAAA==.Pissvibe:BAAALgAECgcJBwAAAA==.Pithius:BAAALgAECgIJAgAAAA==.Pixr:BAAALgAECgcJAQAAAA==.',
Po='Powrwordaddy:BAAALgADCgkJEwABLgAECggJGQATAOYQAA==.',
Pr='Priestler:BAABLgAECn8fAAQeAAgJ4x5rCQCkAgAeAAgJ4x5rCQCkAgALAAcJgxrEHAD1AQAfAAQJFQWOSgA6AAABLgAFFAMJCAADACEgAA==.Primeape:BAABLgAECn8bAAMYAAgJfQ3UFQAkAQAYAAgJSQzUFQAkAQACAAIJ7xNXBgFqAAAAAA==.Prodigal:BAAALgADCgUJBQAAAA==.',
Pu='Pullbarg:BAAALgAECgUJCQAAAA==.Pumpies:BAABLgAECn8WAAIHAAUJmROpEwAEAQAHAAUJmROpEwAEAQAAAA==.Punchdrunk:BAAALgADCgYJDQAAAA==.Purrdruid:BAAALgADCgUJBQAAAA==.',
Py='Pyru:BAAALgAECgIJAgAAAA==.',
['Pà']='Pàngde:BAAALgAECgIJAgAAAA==.',
['Pï']='Pïng:BAABLgAECn8fAAIFAAgJQA6iOgBiAQAFAAgJQA6iOgBiAQAAAA==.',
Qu='Quickkwinter:BAAALgAECgIJAwABLgAECgcJBwAPAAAAAA==.Quickly:BAAALgAECgYJCAAAAA==.Quickwinnter:BAAALgAECgcJBwAAAA==.Quickwinterw:BAAALgAECgEJAQABLgAECgcJBwAPAAAAAA==.',
Ra='Raantoks:BAAALgAECgQJBgAAAA==.Rachet:BAABLgAECn8VAAIVAAYJegcuawD1AAAVAAYJegcuawD1AAAAAA==.Raelilblack:BAAALgAECgYJBwAAAA==.Raideñ:BAAALgAECgIJAwAAAA==.Rakhár:BAAALgAECggJDgAAAA==.Raner:BAAALgADCgMJAwABLgAFFAQJBQAmAD4QAA==.Rashala:BAAALgAECgQJDwAAAA==.Raucahann:BAAALgAECgEJAgAAAA==.Rayado:BAAALgAECgYJEgAAAA==.Razarke:BAABLgAECn8XAAISAAcJXCMTBQCxAgASAAcJXCMTBQCxAgAAAA==.',
Re='Reggienoble:BAACLgAFFH8MAAIKAAQJyhZTBwBYAQAKAAQJyhZTBwBYAQAuAAQKfx8AAgoACAkWJHcCABcDAAoACAkWJHcCABcDAAAA.Rekerî:BAAALgAECgkJDwAAAA==.Reverendmini:BAAALgAECgMJAwAAAA==.Revika:BAAALgAECgQJBAAAAA==.Reynaria:BAACLgAFFH8JAAIlAAMJmx5KEgAHAQAlAAMJmx5KEgAHAQAuAAQKfyQAAyUACAlLIC4JAMACACUACAlLIC4JAMACACYABAlbFFBJAO4AAAAA.Reyyne:BAACLgAFFH8KAAIdAAMJ+R7WFAAJAQAdAAMJ+R7WFAAJAQAuAAQKfycAAh0ACAmtIg8JAN8CAB0ACAmtIg8JAN8CAAAA.',
Ri='Richmage:BAAALgAECgMJBAABLgAFFAUJEAAGAE4dAA==.Rimetail:BAAALgAECgcJDQAAAA==.Rinzee:BAAALgAECgQJBgAAAA==.Rinzlrr:BAAALgAECgUJDAABLgAFFAQJBQAmAD4QAA==.Rioroute:BAAALgADCgkJEQAAAA==.Rivett:BAAALgADCgUJBQAAAA==.',
Ro='Roamer:BAAALgAECgEJAQAAAA==.Roelson:BAAALgADCgEJAQAAAA==.Roflock:BAAALgADCgEJAQAAAA==.Rohrn:BAABLgAECn8eAAIIAAcJ/BQBSQBqAQAIAAcJ/BQBSQBqAQAAAA==.Rol:BAACLgAFFH8MAAIeAAUJgQ6DDQByAQAeAAUJgQ6DDQByAQAuAAQKfxkABB8ACQkWHV0KAKcCAB8ACAn8HV0KAKcCAB4ABQmkFQwwAB8BAAsABAlfGFNBAO4AAAAA.Rolius:BAAALgADCgQJBAAAAA==.Rosenylund:BAAALgAECgYJEgAAAA==.Rotfist:BAAALgADCgUJBQABLgAECggJGwACAIgKAA==.',
Ru='Ruggishbone:BAAALgAECgYJBgAAAA==.',
Ry='Rydia:BAAALgADCgQJBAAAAA==.',
Sa='Safa:BAAALgAECgYJCgABLgAECggJGgABALkbAA==.Saintjudas:BAAALgAECgYJBwAAAA==.Saintsnetie:BAAALgAECgQJCAAAAA==.',
Sc='Scottyknows:BAAALgADCgYJBgAAAA==.Scottymaybe:BAAALgAECggJEgAAAA==.Scredwin:BAABLgAECn8hAAMcAAgJlhtlAgApAgAcAAgJlhtlAgApAgAVAAEJOQOZKQEoAAAAAA==.',
Se='Seancody:BAAALgADCgUJBQAAAA==.Senorbobo:BAACLgAFFH8FAAIWAAMJaxZqDADvAAAWAAMJaxZqDADvAAAuAAQKfyQAAhYACAkPHsYIAJICABYACAkPHsYIAJICAAAA.Serenian:BAAALgAECgYJEQAAAA==.Serni:BAAALgAECgYJCQAAAA==.',
Sh='Shadora:BAAALgAECgYJDwAAAA==.Shadowsbane:BAAALgADCgUJBQAAAA==.Shadowslite:BAAALgAECgEJAQAAAA==.Shadowwolf:BAABLgAECn8hAAIDAAgJrBDnNgA7AQADAAgJrBDnNgA7AQAAAA==.Sham:BAACLgAFFH8GAAIVAAQJchB5JwAiAQAVAAQJchB5JwAiAQAuAAQKfykAAxUACAnyIIgMAIsCABUACAnyIIgMAIsCABwAAgnkD2NYAGUAAAAA.Shamios:BAABLgAECn8YAAIDAAgJ5CB/EQCqAgADAAgJ5CB/EQCqAgAAAA==.Shammknight:BAAALgADCgkJDQAAAA==.Shanksinatrá:BAACLgAFFH8YAAMNAAYJDh8tAgDiAQANAAUJ1iAtAgDiAQAOAAMJnRBFBAAAAQAuAAQKfygAAw0ACQljJngBAK4DAA0ACQlSJngBAK4DAA4ABAlRGnkPABkBAAAA.Shaquira:BAABLgAECn8WAAIFAAgJIgyKMQCHAQAFAAgJIgyKMQCHAQAAAA==.Shatt:BAAALgAECgYJCAAAAA==.Shaxxi:BAABLgAECn8ZAAIDAAgJwxLVJQCdAQADAAgJwxLVJQCdAQAAAA==.Shedari:BAAALgAECgYJBgAAAA==.Shephrah:BAABLgAECn8lAAMlAAkJ/ws0IABFAQAlAAkJ/ws0IABFAQAZAAMJRAWTRwB2AAAAAA==.Shiftalic:BAAALgAFFAMJBAABLgAFFAYJEgAMAOkZAA==.Shifter:BAAALgAECgYJEAAAAA==.Shoshanna:BAAALgAECgIJAgAAAA==.Shourix:BAABLgAECn8mAAIiAAcJ8SQTBgCRAgAiAAcJ8SQTBgCRAgABLgAFFAMJBQAIAPgZAA==.Shploople:BAAALgAECgUJDgAAAA==.Shuckle:BAAALgAECgQJBAABLgAFFAcJFAAaAOkaAA==.Shuppet:BAAALgADCgUJDAAAAA==.',
Si='Sifuicyhot:BAAALgAECgcJDwAAAA==.Sihnn:BAAALgAECgYJBwAAAA==.Simzerker:BAACLgAFFH8TAAIiAAYJsx2yAAD2AQAiAAYJsx2yAAD2AQAuAAQKfxsAAiIACAmHIlcHADMDACIACAmHIlcHADMDAAAA.',
Sk='Skwinkles:BAAALgADCgEJAQAAAA==.',
Sl='Slambulance:BAAALgADCgIJAgAAAA==.Sleepington:BAAALgAECgMJAwAAAA==.Slickrick:BAAALgAECgMJBAAAAA==.Slikshotgrey:BAAALgADCgQJBAAAAA==.Slyvex:BAAALgADCgYJCgAAAA==.',
Sm='Smûsh:BAAALgADCgIJAgAAAA==.',
Sn='Snackum:BAAALgADCgYJBgAAAA==.Snarfca:BAAALgAECgQJBAAAAA==.Sneakthief:BAAALgADCgYJBwAAAA==.Sniiffle:BAABLgAECn8kAAIDAAgJkxpUFQAcAgADAAgJkxpUFQAcAgAAAA==.Snowmage:BAABLgAECn8pAAMbAAkJPB9XAQDKAgAbAAkJPB9XAQDKAgAQAAEJugfQEAAwAAAAAA==.',
So='Soarscha:BAAALgAECgEJAQAAAA==.Softly:BAACLgAFFH8RAAIlAAYJeRfbAQARAgAlAAYJeRfbAQARAgAuAAQKfzoAAiUACQlrJjwAAOcDACUACQlrJjwAAOcDAAAA.Sokan:BAAALgADCgUJBwAAAA==.Somecutty:BAAALgADCgEJAQAAAA==.',
Sp='Spellbeard:BAAALgAECgMJAgAAAA==.Spellcrackle:BAAALgADCgkJEQABLgAECgcJDQAPAAAAAA==.Sploosh:BAAALgADCgEJAQAAAA==.Spùd:BAAALgAECgEJAQAAAA==.',
Sq='Squa:BAACLgAFFH8JAAMNAAMJUSWxDwArAQANAAMJUSWxDwArAQAOAAIJ3gkEBAC1AAAuAAQKfx8AAw0ACAmnIqEKAOgCAA0ACAmnIqEKAOgCAA4ABAlyHHgMAFwBAAAA.Squishdemon:BAAALgADCgEJAQAAAA==.Squî:BAAALgAFFAEJAQABLgAFFAMJCQANAFElAA==.',
Ss='Ssudds:BAAALgAECgYJCwABLgAECgkJLQAQAC4fAA==.Ssuddychan:BAAALgAECggJEgABLgAECgkJLQAQAC4fAA==.',
St='Stalagstrype:BAABLgAECn8bAAIIAAgJ6B3eFABSAgAIAAgJ6B3eFABSAgAAAA==.Stankfu:BAAALgADCgQJBAAAAA==.Starkisses:BAABLgAECn8vAAIFAAkJayMfAgAtAwAFAAkJayMfAgAtAwAAAA==.Steeb:BAAALgAECgQJBAAAAA==.Stenkeydk:BAABLgAECn8sAAMCAAkJKxSCIAAHAgACAAkJKxSCIAAHAgAEAAEJGgJDGQAjAAAAAA==.Steve:BAAALgAECgQJBAABLgAECgIJAgAPAAAAAA==.Stonepaw:BAAALgADCgQJBAAAAA==.Stopthecapp:BAACLgAFFH8FAAIIAAMJ+Bl4KQAHAQAIAAMJ+Bl4KQAHAQAuAAQKfy0AAggACAkxJU8IAFEDAAgACAkxJU8IAFEDAAAA.Storebrand:BAAALgADCgcJCAABLgAECgIJAgAPAAAAAA==.Storebrandps:BAAALgADCgcJDAABLgAECgIJAgAPAAAAAA==.Stratego:BAAALgADCgUJDgAAAA==.Styrthe:BAACLgAFFH8bAAQZAAcJ+h8wBQCCAQAZAAUJnxwwBQCCAQAlAAQJ0RPmEgAAAQAmAAEJKAT0IgA/AAAuAAQKfyIAAxkACQmDGfIRAIUCABkACQmDGfIRAIUCACUABwkRETAuAEcBAAAA.',
Su='Subotae:BAAALgADCgMJAwAAAA==.Surfacing:BAAALgAECgcJDQAAAA==.Surventval:BAAALgAECgcJEwABLgAFFAQJBQAmAD4QAA==.',
Sw='Swindler:BAABLgAECn8cAAMCAAgJ0B86EgBqAgACAAgJ0B86EgBqAgAYAAYJIhUBHQBjAQAAAA==.Swollstone:BAABLgAECn8ZAAIVAAYJvA1ZWQAhAQAVAAYJvA1ZWQAhAQAAAA==.',
Sy='Symphony:BAACLgAFFH8JAAIMAAMJLB7CJQAaAQAMAAMJLB7CJQAaAQAuAAQKfycAAgwACAlsHgwQAEMCAAwACAlsHgwQAEMCAAAA.Syzegy:BAAALgAECgEJAwAAAA==.',
Ta='Taeka:BAAALgAECgUJDAAAAA==.Talkimas:BAABLgAECn8mAAQKAAkJexj2CQAEAgAGAAgJNBqhGwBLAgAKAAkJEhD2CQAEAgAFAAEJAAArwQBDAAAAAA==.Talvisota:BAABLgAECn8rAAICAAgJSSEBDQCdAgACAAgJSSEBDQCdAgAAAA==.Tankthor:BAABLgAECn8sAAMiAAkJNxBZDwD9AQAiAAkJLxBZDwD9AQAWAAcJcgnnIgAnAQAAAA==.Tarirn:BAACLgAFFH8JAAICAAIJSx0yPQCkAAACAAIJSx0yPQCkAAAuAAQKfxQAAgIACAl+G3dSAPoBAAIACAl+G3dSAPoBAAAA.Tazgrim:BAAALgAECgcJEgAAAA==.',
Te='Teflondon:BAAALgADCgQJBwAAAA==.Teknar:BAAALgAECgMJAwAAAA==.Tekos:BAAALgAECgQJBgABLgAFFAQJCwAkAM4VAA==.Tekoslul:BAACLgAFFH8LAAIkAAQJzhUEBQBPAQAkAAQJzhUEBQBPAQAuAAQKfxkAAyQACQkBJDECAHQDACQACQkBJDECAHQDAAwABAmXFjiPAAIBAAAA.Tekosp:BAAALgAECgMJBAABLgAFFAQJCwAkAM4VAA==.Tekosxd:BAAALgAECgEJAwABLgAFFAQJCwAkAM4VAA==.Telawolf:BAAALgADCggJCAAAAA==.Teldrussy:BAAALgAECggJCQABLgAECggJJwAfAC4fAA==.Telorian:BAABLgAECn8YAAIMAAgJpx7uJAB1AgAMAAgJpx7uJAB1AgAAAA==.Tendeda:BAAALgAECgUJCAAAAA==.Terrasite:BAAALgAECgQJBAAAAA==.',
Th='Thalunar:BAABLgAECn8YAAIFAAgJSBy6JAAqAgAFAAgJSBy6JAAqAgAAAA==.Thatonedruid:BAAALgAECgUJBQABLgAFFAMJBQAWAGsWAA==.Thejw:BAAALgAECgYJEgAAAA==.Thrallzballz:BAAALgADCgYJBwAAAA==.Thrdeyethump:BAAALgAECgYJCQAAAA==.Thörck:BAABLgAECn8VAAMSAAgJ8gV9CAAlAQASAAgJ5QV9CAAlAQARAAgJiwNELwDpAAAAAA==.',
Ti='Tigersu:BAAALgAFFAEJAQAAAA==.Tinklewinkle:BAABLgAECn8qAAIbAAkJMiE8AAACAwAbAAkJMiE8AAACAwAAAA==.Titanrb:BAAALgADCgcJCwAAAA==.',
Tj='Tjaili:BAAALgAECgcJDwAAAA==.',
To='Tocks:BAAALgAECgQJBQAAAA==.Toco:BAAALgAECgQJBAABLgAECgYJHgAhAEMiAA==.Toge:BAABLgAECn8VAAMBAAgJjSEtOQCRAgABAAgJjSEtOQCRAgAbAAEJ9AzwHgAzAAABLgAFFAcJEwAhADsVAA==.Tokapolo:BAABLgAECn8eAAIhAAYJQyIAFQCsAQAhAAYJQyIAFQCsAQAAAA==.Toluene:BAAALgAECgEJAQAAAA==.Topshelfelf:BAABLgAECn8sAAMeAAgJxhY/DwDeAQAeAAgJ7xQ/DwDeAQAfAAIJGAq0SgA6AAAAAA==.Torver:BAAALgAECgkJEwAAAA==.Totemsquish:BAAALgADCgEJAQAAAA==.',
Tr='Treemother:BAABLgAECn8qAAIDAAcJLhopHQDaAQADAAcJLhopHQDaAQAAAA==.Treewa:BAAALgAFFAEJAgAAAA==.Treezon:BAAALgADCgMJAwAAAA==.Tresdin:BAACLgAFFH8GAAIIAAQJKAhIIgAkAQAIAAQJKAhIIgAkAQAuAAQKfxsAAggACQncG5YvAL4BAAgACQncG5YvAL4BAAAA.',
Ts='Tsohg:BAAALgADCgYJCAAAAA==.',
Tu='Tuhalla:BAABLgAECn8dAAIIAAkJwQpPRwBvAQAIAAkJwQpPRwBvAQAAAA==.Tumlock:BAABLgAECn8iAAMcAAcJSAzrDgDlAAAVAAcJxgkDbAD0AAAcAAYJ+wnrDgDlAAAAAA==.Turbulence:BAAALgAECgQJBAAAAA==.',
Tw='Twl:BAAALgAECgQJCAAAAA==.',
['Tï']='Tïgra:BAABLgAECn8uAAIMAAkJUCHAAwD+AgAMAAkJUCHAAwD+AgAAAA==.',
Ua='Uandikillhim:BAABLgAECn8iAAIeAAgJ2h4mCAC9AgAeAAgJ2h4mCAC9AgAAAA==.',
Ul='Uldren:BAAALgAECgIJAgABLgAECgkJKQANABIdAA==.',
Un='Uncompetent:BAAALgADCgEJAQAAAA==.Undeadbones:BAAALgAECgQJCAAAAA==.Unfading:BAABLgAECn8uAAIIAAkJRx2yCwClAgAIAAkJRx2yCwClAgAAAA==.Unholyknight:BAAALgAECgcJDQAAAA==.Uninfluenced:BAAALgAECgQJBQAAAA==.Unoo:BAAALgAECgQJBAAAAA==.',
Ur='Uranus:BAABLgAECn8aAAIFAAYJqx41MACNAQAFAAYJqx41MACNAQAAAA==.Urban:BAAALgADCgEJAQAAAA==.Urtark:BAACLgAFFH8FAAIiAAIJWR+cHwCtAAAiAAIJWR+cHwCtAAAuAAQKfycAAiIACQmIHpoPAPoBACIACQmIHpoPAPoBAAAA.',
Va='Vadym:BAAALgAECgUJCgAAAA==.Vaelia:BAAALgAECggJDgAAAA==.Vainquish:BAAALgAECgYJDQAAAA==.Valeriann:BAAALgADCgMJAwAAAA==.Valorias:BAACLgAFFH8GAAIeAAMJOwbYGgDJAAAeAAMJOwbYGgDJAAAuAAQKfyEAAh4ACAk+G+UMAGoCAB4ACAk+G+UMAGoCAAAA.Vankwish:BAABLgAECn8hAAMbAAcJuxbYBwB/AQABAAcJpRUESgCKAQAbAAYJFxTYBwB/AQAAAA==.Vanquith:BAAALgAECgEJAQAAAA==.Varalic:BAAALgAFFAIJAgABLgAFFAYJEgAMAOkZAA==.Varandra:BAAALgADCgMJAwABLgAECgMJAwAPAAAAAA==.Vareesa:BAAALgAECgMJAwAAAA==.Vaulken:BAAALgAECgcJDQAAAA==.Vañquish:BAAALgADCgEJAQAAAA==.',
Ve='Veggyfruit:BAAALgAECgYJEgAAAA==.Ventrois:BAACLgAFFH8FAAImAAQJPhDLCQAyAQAmAAQJPhDLCQAyAQAuAAQKfyUAAiYABwnvHxgPAMkBACYABwnvHxgPAMkBAAAA.Verdarts:BAAALgADCgcJBwAAAA==.Veregas:BAABLgAECn8ZAAIdAAgJrRuZFQDjAQAdAAgJrRuZFQDjAQAAAA==.Vermilion:BAAALgADCgYJCwAAAA==.Vesseven:BAACLgAFFH8IAAIiAAMJ9RaUFgD6AAAiAAMJ9RaUFgD6AAAuAAQKfx4AAiIACAlXHvcXAIwCACIACAlXHvcXAIwCAAAA.',
Vi='Vilienar:BAAALgAECgMJAwAAAA==.Vimao:BAAALgAECgMJAwAAAA==.Vizzy:BAAALgADCgcJBwAAAA==.',
Vo='Voidalic:BAACLgAFFH8SAAIMAAYJ6RkECwCbAQAMAAYJ6RkECwCbAQAuAAQKfxsAAgwACAkJIzQUAN8CAAwACAkJIzQUAN8CAAAA.Voidrend:BAACLgAFFH8SAAMMAAcJTxBQBgDTAQAMAAYJTxBQBgDTAQAXAAIJ4AP/BQA2AAAuAAQKfykAAgwACQlbIRcJAD8DAAwACQlbIRcJAD8DAAAA.Voimasta:BAAALgADCgIJAgAAAA==.',
Vu='Vuloolu:BAABLgAECn8ZAAIDAAgJ7A+GKgCAAQADAAgJ7A+GKgCAAQAAAA==.Vulpiena:BAAALgADCgcJBwAAAA==.Vulvaenjoyer:BAAALgAECgcJBwAAAA==.',
['Vî']='Vî:BAAALgAECgcJDgAAAA==.Vîews:BAAALgAECggJEwAAAA==.',
['Vø']='Vøgue:BAABLgAECn8wAAIOAAkJRBXAAgAlAgAOAAkJRBXAAgAlAgAAAA==.',
Wa='Warbidet:BAAALgAECgEJAgAAAA==.Warlockwally:BAAALgAECgUJDAAAAA==.Warloko:BAABLgAECn8ZAAIUAAgJHx1FAQBiAgAUAAgJHx1FAQBiAgAAAA==.Warmason:BAABLgAECn8rAAIWAAgJ/BR5DQCLAQAWAAgJ/BR5DQCLAQAAAA==.Warpheal:BAAALgADCgkJCgABLgAECggJKAAhAEgfAA==.Warrida:BAAALgADCgEJAQAAAA==.Washed:BAABLgAECn8gAAMVAAgJtRQ6OQCBAQAVAAcJoRU6OQCBAQAcAAQJrw1DRQCgAAAAAA==.',
We='Wealthy:BAABLgAECn8sAAMeAAkJfh2dAgAeAwAeAAkJQR2dAgAeAwAfAAYJOBcELwCHAQAAAA==.Wearkit:BAAALgADCgQJBAAAAA==.Weßall:BAAALgADCgcJBwAAAA==.',
Wh='Whiskeydix:BAAALgADCgYJBgAAAA==.Whyisitdark:BAAALgADCgUJBQAAAA==.',
Wi='Wiiska:BAAALgAECgYJBgAAAA==.Wildassassjd:BAAALgADCgUJBQABLgAECgYJCAAPAAAAAA==.',
Wo='Wonderful:BAAALgADCgMJAwAAAA==.',
Wr='Wrakk:BAABLgAECn8hAAINAAgJdBNjDQDMAQANAAgJdBNjDQDMAQAAAA==.Wrred:BAAALgAECgUJDwAAAA==.',
Xo='Xombi:BAAALgADCgQJBAABLgAECgYJCAAPAAAAAA==.',
Xt='Xtik:BAAALgADCgcJBwAAAA==.',
Yb='Ybeavg:BAAALgADCggJCAAAAA==.',
Yd='Ydduss:BAAALgAECgcJDQABLgAECgkJLQAQAC4fAA==.',
Ye='Yeahbuddy:BAAALgADCgQJBAAAAA==.',
Yu='Yumbus:BAAALgAECggJCAAAAA==.Yunai:BAAALgAECgEJAQAAAA==.',
Ze='Zemi:BAABLgAECn8wAAIgAAkJQhe0AwBBAgAgAAkJQhe0AwBBAgAAAA==.Zeneragor:BAAALgAECgQJBAAAAA==.Zenethrius:BAAALgADCgMJAwAAAA==.Zevalia:BAABLgAECn8fAAMlAAcJOBr0JwB1AQAlAAYJHxj0JwB1AQAZAAYJOA9/JQAUAQAAAA==.Zevarya:BAAALgADCgEJAQABLgAECgcJHwAlADgaAA==.Zevelyon:BAAALgADCgEJAQABLgAECgcJHwAlADgaAA==.',
Zo='Zophia:BAAALgAECgEJAQAAAA==.Zorak:BAAALgAECgIJAgABLgAFFAMJCgAdAPkeAA==.',
Zt='Ztoned:BAAALgADCgUJBgAAAA==.',
Zu='Zubby:BAABLgAECn8cAAIVAAcJryCcJADYAQAVAAcJryCcJADYAQAAAA==.Zuddy:BAAALgADCgUJBQAAAA==.Zugrotic:BAAALgAECgYJCQAAAA==.Zugtrek:BAAALgADCgEJAQAAAA==.Zulakunda:BAAALgAECgYJEwAAAA==.Zummey:BAAALgADCgcJBAAAAA==.',
Zy='Zylox:BAABLgAECn8bAAILAAgJqhALFQCZAQALAAgJqhALFQCZAQAAAA==.',
['Zë']='Zëüs:BAABLgAECn8aAAITAAcJKg9+EgAZAQATAAcJKg9+EgAZAQAAAA==.',
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
