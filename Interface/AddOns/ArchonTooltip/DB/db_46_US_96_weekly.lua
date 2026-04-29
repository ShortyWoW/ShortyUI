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

local lookup = {'Mage-Frost','DeathKnight-Unholy','Druid-Restoration','Hunter-BeastMastery','Hunter-Marksmanship','Evoker-Preservation','Paladin-Retribution','Druid-Feral','Hunter-Survival','Rogue-Subtlety','Rogue-Assassination','Unknown-Unknown','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Devastation','Warlock-Affliction','Warlock-Demonology','DemonHunter-Vengeance','DeathKnight-Blood','Monk-Brewmaster','Mage-Arcane','Warlock-Destruction','Priest-Discipline','Priest-Holy','Warrior-Fury','Warrior-Protection','Paladin-Holy','Druid-Balance','DemonHunter-Havoc','Shaman-Elemental','Shaman-Restoration','Paladin-Protection','Priest-Shadow','Monk-Mistweaver','Shaman-Enhancement','Monk-Windwalker','Warrior-Arms','Druid-Guardian','DeathKnight-Frost','Mage-Fire',}
local provider = {region='US',realm='Firetree',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abacabb:BAAALgAECgQJBAAAAA==.',
Ad='Adnarimn:BAAALgAECgEJAQAAAA==.Adondias:BAABLgAECn8ZAAIBAAgJSyErHQABAwABAAgJSyErHQABAwAAAA==.',
Ae='Aelanthus:BAAALgADCgEJAQAAAA==.',
Ag='Agrevail:BAAALgAECgQJBwAAAA==.',
Ai='Aidendk:BAABLgAECn8YAAICAAgJlx/MJACqAgACAAgJlx/MJACqAgAAAA==.',
Ak='Akrib:BAAALgADCgUJBQAAAA==.Akryllic:BAABLgAECn8WAAIDAAYJ9BvuNADUAQADAAYJ9BvuNADUAQAAAA==.',
Al='Aldari:BAACLgAFFH8IAAIBAAMJIByCDQAkAQABAAMJIByCDQAkAQAuAAQKfxoAAgEACQndJO4HAIoDAAEACQndJO4HAIoDAAAA.Allen:BAAALgADCgcJBwAAAA==.Allydk:BAABLgAECn8eAAICAAkJ8SFWGQDkAgACAAkJ8SFWGQDkAgAAAA==.Altrag:BAABLgAECn8gAAMEAAkJ/hvUAQCcAgAEAAkJ/hvUAQCcAgAFAAEJmAHamQAaAAAAAA==.Aluc:BAABLgAECn8aAAIGAAgJIw2+GQC/AQAGAAgJIw2+GQC/AQAAAA==.',
An='Andilar:BAABLgAECn8YAAIHAAcJ2BpBRgARAgAHAAcJ2BpBRgARAgAAAA==.Andrepov:BAAALgAECgEJBAAAAA==.Anehii:BAABLgAECn8dAAIIAAgJ4geVEwB3AQAIAAgJ4geVEwB3AQAAAA==.Aniia:BAAALgAECgYJCQAAAA==.Animaldude:BAABLgAECn8nAAMJAAgJZx8pBQC9AgAJAAgJZx8pBQC9AgAFAAEJ3gRTkAAqAAAAAA==.Anjera:BAAALgAECgYJDgAAAA==.Anotherdrood:BAAALgAECgYJBgAAAA==.Anslayer:BAAALgAECgEJAQAAAA==.Anémie:BAAALgADCgkJDwAAAA==.',
Ap='Apexis:BAAALgAECgYJEQAAAA==.Apolion:BAAALgAECgMJBAAAAA==.',
Ar='Arctodus:BAAALgAECgYJCgAAAA==.Arghuul:BAABLgAECn8pAAMKAAkJEh1zBwAZAwAKAAkJEh1zBwAZAwALAAEJ4RuhGgBTAAAAAA==.Arks:BAAALgAFFAEJAQAAAA==.Arksmash:BAAALgADCgcJBwAAAA==.',
As='Asperges:BAAALgAECggJEwAAAA==.Astropâ:BAAALgAECgEJAQAAAA==.',
Ax='Axsisdknight:BAAALgAECgEJAQAAAA==.',
Az='Azasei:BAAALgADCgMJBAAAAA==.Azathoth:BAAALgADCgUJBwABLgADCgcJDAAMAAAAAA==.',
['Aë']='Aëlana:BAABLgAECn8cAAIBAAgJzBmkRgBkAgABAAgJzBmkRgBkAgAAAA==.',
Ba='Babems:BAAALgADCgIJAgAAAA==.Baconn:BAACLgAFFH8HAAIHAAQJOxqPCQBhAQAHAAQJOxqPCQBhAQAuAAQKfx4AAgcABwnuJCcfALECAAcABwnuJCcfALECAAAA.Bailey:BAAALgADCgQJBAAAAA==.Balkhan:BAAALgADCgMJAwAAAA==.Balun:BAAALgAECgEJAwAAAA==.Banza:BAAALgAECgEJAQAAAA==.Barsh:BAABLgAECn8YAAINAAYJThnRTADBAQANAAYJThnRTADBAQABLgAECggJGwABAAggAA==.',
Be='Beauregarde:BAAALgADCggJBgAAAA==.Beef:BAACLgAFFH8KAAIOAAQJtxyiCABkAQAOAAQJtxyiCABkAQAuAAQKfxoAAw4ACAkHJvMFACQDAA4ACAl4I/MFACQDAA8ABAlBJQ8UAKUBAAAA.Beefdido:BAABLgAECn8cAAILAAgJ9RQeAQDmAQALAAgJ9RQeAQDmAQAAAA==.Beefstew:BAAALgAECgMJAwAAAA==.Befouled:BAAALgAECgcJEQAAAA==.Belinos:BAAALgADCgEJAQAAAA==.Belithe:BAAALgAECgQJDAAAAA==.Benson:BAAALgADCgIJAgAAAA==.Berrymanalow:BAABLgAECn8bAAIBAAgJqBCBZAAPAgABAAgJqBCBZAAPAgAAAA==.',
Bi='Bigpapapumpz:BAAALgAECgYJBwAAAA==.Bijtoo:BAABLgAECn8ZAAMQAAcJ/RtxBAA3AgAQAAcJ/RtxBAA3AgARAAIJHg979QBuAAAAAA==.Bingsoo:BAABLgAECn8eAAIBAAkJvBa8SgBXAgABAAkJvBa8SgBXAgAAAA==.Bist:BAAALgAECgUJBwABLgAECgcJHgAHAI0lAA==.Bistopher:BAABLgAECn8eAAIHAAcJjSUAFADzAgAHAAcJjSUAFADzAgAAAA==.Bisty:BAAALgADCgYJCgABLgAECgcJHgAHAI0lAA==.',
Bj='Bjorney:BAAALgAECgcJDQAAAA==.',
Bl='Blankspace:BAAALgAECgUJCgAAAA==.Blaserr:BAAALgAECggJEgAAAA==.Blessurface:BAAALgAECgIJAgAAAA==.Blindfire:BAABLgAECn8hAAIBAAkJ8x1gHAAFAwABAAkJ8x1gHAAFAwAAAA==.Blindspirit:BAAALgAECgYJDAAAAA==.Blindvngence:BAABLgAECn8WAAISAAgJ1BSeCADuAQASAAgJ1BSeCADuAQAAAA==.Blizzerker:BAAALgAECgEJAQAAAA==.Bloodrayne:BAAALgADCgUJDAAAAA==.Bludoosh:BAAALgAECgYJDQAAAA==.Blumken:BAAALgADCgEJAQAAAA==.',
Bo='Bombpops:BAAALgADCgEJAQABLgAECggJHQAHAGYaAA==.Bonkdeath:BAABLgAECn8VAAMCAAcJKAkMMgC7AAACAAYJDgoMMgC7AAATAAEJqgTmFQAiAAAAAA==.Boomskii:BAAALgADCgIJAgAAAA==.Boomymonk:BAABLgAECn8XAAIUAAcJsR8xFABuAgAUAAcJsR8xFABuAgABLgAFFAEJAQAMAAAAAA==.',
Br='Br:BAABLgAECn8YAAIDAAkJmh9dBQA3AwADAAkJmh9dBQA3AwAAAA==.Brauxx:BAAALgADCgYJBgAAAA==.Breadermonk:BAAALgAECgYJEQAAAA==.Brezanyou:BAAALgAECgYJEgAAAA==.Broly:BAAALgADCgcJDAAAAA==.Brotherblud:BAAALgADCgkJCgAAAA==.Brøx:BAABLgAECn8aAAICAAcJxxdKDgCoAQACAAcJxxdKDgCoAQAAAA==.',
Bu='Bubbelhearth:BAAALgAECgYJDAAAAA==.Budyzer:BAAALgADCgYJBgAAAA==.Builtdif:BAAALgADCgYJBgABLgAECggJJAAHAFwjAA==.Bumbaclottx:BAAALgAECgMJBAAAAA==.Bunnyboy:BAAALgAECgQJCAAAAA==.Burlen:BAABLgAECn8aAAMBAAgJuRvQRwBgAgABAAgJuRvQRwBgAgAVAAQJxBpkDQDyAAAAAA==.Bustarime:BAAALgADCgkJHAAAAA==.Buyagram:BAAALgADCgIJAQAAAA==.',
Bw='Bwonsamdeez:BAAALgADCgYJBgAAAA==.',
['Bî']='Bîrth:BAABLgAECn8eAAIBAAgJVB7zLAC+AgABAAgJVB7zLAC+AgAAAA==.',
Ca='Caeleste:BAAALgAECgQJBQAAAA==.Calic:BAABLgAECn8cAAMWAAgJ4BhnBgBpAgAWAAgJ4BhnBgBpAgARAAMJtQvo5QCPAAAAAA==.Calryuu:BAAALgAECgYJEgAAAA==.Caltrask:BAAALgAECgIJAgAAAA==.Cambiön:BAABLgAECn8cAAIBAAgJCxW/WAAvAgABAAgJCxW/WAAvAgAAAA==.Cameltoetem:BAAALgAECgQJAwAAAA==.Canape:BAAALgAECgQJEwAAAA==.Capnmurlock:BAAALgADCgEJAQAAAA==.Captnmurzzp:BAAALgADCgkJDgAAAA==.Carpetcrumbs:BAAALgAECgEJAQAAAA==.Castasaurus:BAAALgAECgQJBAAAAA==.Catharsis:BAACLgAFFH8SAAMXAAYJdiIYAQDqAQAXAAYJICIYAQDqAQAYAAEJHCUnEQBiAAAuAAQKfyAAAxcACQn5JSAAAOkDABcACQn5JSAAAOkDABgABwlYJQkKAKwCAAAA.',
Ce='Ceer:BAAALgADCggJDQAAAA==.Cenno:BAABLgAECn8cAAICAAgJsBCRYQDOAQACAAgJsBCRYQDOAQAAAA==.',
Ch='Charlixcx:BAAALgADCgEJAQAAAA==.Chickenman:BAAALgAECgcJDgAAAA==.Chickienuggs:BAAALgADCgcJCgAAAA==.Chiflado:BAAALgAECgcJCwAAAA==.Chillinda:BAAALgAECgIJBQAAAA==.Chillpoppin:BAAALgAECgYJEQAAAA==.Chinpokomon:BAAALgAECgkJKAAAAQ==.Chompsy:BAABLgAECn8dAAIBAAgJrxm7QQBzAgABAAgJrxm7QQBzAgAAAA==.Chubbychi:BAAALgAECgEJAQABLgAECgYJEgAMAAAAAA==.',
Ci='Ciei:BAAALgADCgIJAgAAAA==.Cilya:BAAALgAECgYJCAAAAA==.Citrusghoul:BAAALgAECgYJDQAAAA==.Citruslite:BAAALgAECgEJAQAAAA==.',
Cl='Clockworkx:BAAALgAECgEJAQAAAA==.',
Co='Cole:BAABLgAECn8aAAMZAAYJ9iDxBwCiAQAZAAYJ9iDxBwCiAQAaAAQJsxJaLQDXAAAAAA==.Conceptheals:BAAALgAECgUJBgAAAA==.Confessia:BAAALgAECgYJBwAAAA==.Constantine:BAAALgADCgcJBwAAAA==.Costcobeef:BAAALgAECgEJAQABLgAECgIJAgAMAAAAAA==.Couchlocked:BAAALgADCgEJAQAAAA==.',
Cr='Crackle:BAAALgAECgMJAwAAAA==.Criticalmiss:BAAALgAECgMJBAABLgAFFAQJDQACANAYAA==.Critsae:BAACLgAFFH8JAAICAAQJHRmBDwBjAQACAAQJHRmBDwBjAQAuAAQKfx8AAgIACAk2IFYWAPYCAAIACAk2IFYWAPYCAAAA.Critydarkirn:BAABLgAECn8fAAMbAAgJGx7kHAAvAgAbAAgJGx7kHAAvAgAHAAUJnBEsIwAeAQAAAA==.Crypticdh:BAAALgAECgcJEQAAAA==.Cryptø:BAAALgAECgYJBwAAAA==.',
Cv='Cvrcvss:BAABLgAECn8ZAAQRAAgJGhNPYQClAQARAAcJlRNPYQClAQAWAAUJhg4XKQAeAQAQAAEJAABrLgBBAAAAAA==.',
Cy='Cybele:BAABLgAECn8dAAINAAcJXCCeCADoAQANAAcJXCCeCADoAQAAAA==.Cypriss:BAAALgAECgEJAgAAAA==.',
['Cë']='Cëlestial:BAAALgAECgYJBwAAAA==.',
Da='Dabadjuju:BAAALgAECgQJBQAAAA==.Dagoonfather:BAAALgAECggJDgAAAA==.Dale:BAAALgADCgMJAwAAAA==.Dandorllan:BAACLgAFFH8IAAIbAAIJ6CCwEQDBAAAbAAIJ6CCwEQDBAAAuAAQKfx4AAxsACQkHI0ABAHgDABsACQkHI0ABAHgDAAcACAnEHnYgAKoCAAEuAAUUAwkEAAwAAAAA.Dandowaz:BAAALgAFFAMJBAAAAA==.Dandyrandy:BAABLgAECn8eAAMHAAkJXA2JWADZAQAHAAkJXA2JWADZAQAbAAgJJRGpLgDJAQAAAA==.Dani:BAAALgADCgUJCQAAAA==.Dareick:BAAALgAECgQJDAAAAA==.Darthashmire:BAAALgAECgQJBQAAAA==.Darthavenger:BAAALgAECgYJDAAAAA==.Dayday:BAABLgAECn8aAAIcAAgJ0hDSBwB7AQAcAAgJ0hDSBwB7AQAAAA==.Dazzazn:BAAALgAECgQJCQAAAA==.',
De='Decious:BAABLgAECn8aAAIHAAgJ5BrhNwBDAgAHAAgJ5BrhNwBDAgAAAA==.Deepfist:BAABLgAECn8bAAIUAAgJnxoAFgBaAgAUAAgJnxoAFgBaAgAAAA==.Deepfried:BAAALgAECgMJBAAAAA==.Defjam:BAABLgAECn8dAAIBAAcJBxxQVgA2AgABAAcJBxxQVgA2AgAAAA==.Delath:BAAALgAECgIJAgAAAA==.Delicia:BAAALgAECgYJEgAAAA==.Dellbelphine:BAABLgAECn8eAAIHAAgJEhgxRQAUAgAHAAgJEhgxRQAUAgAAAA==.Deminis:BAAALgADCgYJBgAAAA==.Demonbud:BAAALgAECgIJAwABLgAECggJEwAMAAAAAA==.Demoncarlos:BAACLgAFFH8HAAINAAMJZRR2HQDpAAANAAMJZRR2HQDpAAAuAAQKfyMAAg0ACAkNIQgeAJ4CAA0ACAkNIQgeAJ4CAAAA.Demonicscale:BAABLgAECn8gAAMRAAgJSRE/TwDaAQARAAgJSRE/TwDaAQAQAAEJSAXNNQAuAAAAAA==.Demonskii:BAABLgAECn8bAAIdAAgJWB6YCADZAgAdAAgJWB6YCADZAgAAAA==.Demton:BAABLgAECn8dAAIdAAgJfxxkDACbAgAdAAgJfxxkDACbAgAAAA==.Denken:BAABLgAFFH8MAAIeAAUJdBXhAACeAQAeAAUJdBXhAACeAQAAAA==.Deuslucis:BAAALgADCgEJAQAAAA==.Dezmage:BAEALgADCgYJBgAAAA==.Dezpriest:BAAALgADCgcJDQAAAA==.',
Di='Diatonic:BAAALgADCgIJAgABLgAECggJGwANAMEcAA==.Dildrathion:BAAALgAECgYJBgAAAA==.Direkau:BAABLgAECn8eAAIaAAkJzCL9AgAxAwAaAAkJzCL9AgAxAwAAAA==.Divinity:BAAALgAECgYJBgAAAA==.Diwata:BAACLgAFFH8OAAIXAAUJuxdVAgCbAQAXAAUJuxdVAgCbAQAuAAQKfyYAAxcACAmoHVgKAJMCABcACAmeHVgKAJMCABgABgnNDvY9AEIBAAAA.',
Do='Dogler:BAABLgAECn8YAAMDAAgJ3yOICwDkAgADAAgJ3yOICwDkAgAcAAYJwBmNBwCBAQABLgAECggJHwAXAOMeAA==.Dojaz:BAABLgAECn8WAAMNAAkJTApHXwCDAQANAAkJRwpHXwCDAQAdAAIJqAmsXwBjAAAAAA==.Doki:BAAALgADCgQJBAAAAA==.Domeydome:BAAALgAECgEJAQAAAA==.Donthitgary:BAAALgAECgIJAgAAAA==.Dooley:BAAALgAECggJEwAAAA==.Doomgrapple:BAAALgADCgEJAwAAAA==.Doriahn:BAAALgAECgYJDAAAAA==.',
Dr='Draconica:BAAALgAECggJEwAAAA==.Dracussy:BAABLgAECn8cAAMOAAkJJhW8EwBGAgAOAAkJJhW8EwBGAgAPAAIJkA7aNABtAAAAAA==.Dragar:BAABLgAECn8fAAIZAAgJBBd0BAD0AQAZAAgJBBd0BAD0AQAAAA==.Dragoon:BAAALgAECgUJBQAAAA==.Draktha:BAAALgAECgQJBAABLgAECgcJFwAPAFwjAA==.Dreamchaser:BAAALgADCgUJBQAAAA==.Dreddful:BAAALgAECgEJAwAAAA==.Drkelso:BAABLgAECn8ZAAIBAAcJDQvbHQBhAQABAAcJDQvbHQBhAQAAAA==.Dropswitch:BAAALgADCgEJAQAAAA==.Drpeppah:BAAALgADCgEJAgAAAA==.',
Du='Duchalu:BAABLgAECn8dAAIZAAgJlRHjLQD7AQAZAAgJlRHjLQD7AQAAAA==.Durtbag:BAAALgADCgQJBwAAAA==.',
Dw='Dwarrfie:BAAALgAECgUJBgAAAA==.',
Dy='Dynabear:BAAALgADCgQJCQAAAA==.',
['Dè']='Dèz:BAAALgAECgYJEQAAAA==.',
['Dú']='Dúncan:BAAALgAECgYJBgAAAA==.',
Ei='Eione:BAABLgAECn8aAAIcAAYJ6xg9CwA6AQAcAAYJ6xg9CwA6AQAAAA==.',
El='Elaswyn:BAAALgAECgMJBAAAAA==.Elemantary:BAAALgAECgcJCAAAAA==.Elfieras:BAAALgAECgIJAgAAAA==.Elfies:BAAALgADCgYJBwAAAA==.Elinez:BAAALgAECgEJAQAAAA==.Ellcrys:BAABLgAECn8XAAIWAAgJ3wlqFwCOAQAWAAgJ3wlqFwCOAQAAAA==.Elvinshiznic:BAAALgAECgYJCgAAAA==.Elyzah:BAAALgAFFAEJAgAAAA==.',
Em='Emagine:BAABLgAECn8cAAIfAAgJWx2rFgBhAgAfAAgJWx2rFgBhAgAAAA==.Emeraldbeast:BAACLgAFFH8JAAIDAAMJrw+nEQDcAAADAAMJrw+nEQDcAAAuAAQKfxwAAgMACAk2G2gaAGcCAAMACAk2G2gaAGcCAAAA.',
En='Enni:BAABLgAECn8gAAINAAgJIyMEEAD+AgANAAgJIyMEEAD+AgAAAA==.',
Er='Erengarde:BAABLgAECn8XAAIbAAgJExkWFwBZAgAbAAgJExkWFwBZAgAAAA==.Eri:BAAALgAECgQJBgAAAA==.Erissra:BAABLgAECn8ZAAMQAAkJAgxXBwDfAQAQAAgJ4wxXBwDfAQARAAYJygXhswDxAAAAAA==.Eroeda:BAABLgAECn8YAAIdAAYJOBI4LwBUAQAdAAYJOBI4LwBUAQAAAA==.',
Es='Escanør:BAAALgAECgQJBQABLgAECgcJDgAMAAAAAA==.',
Ex='Exelero:BAAALgAECgMJCgAAAA==.Exil:BAAALgADCgcJCgAAAA==.Exo:BAABLgAECn8eAAIDAAkJMyMDBQA+AwADAAkJMyMDBQA+AwAAAA==.Exosham:BAAALgADCgMJAwABLgAECgkJHgADADMjAA==.',
Ey='Eynya:BAAALgADCgcJBwABLgAECgQJCAAMAAAAAA==.',
Ez='Ezfrost:BAAALgAECgUJDAAAAA==.Ezsmash:BAABLgAECn8YAAIZAAcJsR3+IQBEAgAZAAcJsR3+IQBEAgAAAA==.',
['Eñ']='Eñkei:BAAALgADCgIJAwAAAA==.',
Fa='Faeline:BAAALgAECgIJAgAAAA==.Familiarface:BAAALgAECgYJDQAAAA==.Fastfeet:BAAALgAFFAQJBAAAAA==.',
Fe='Felam:BAAALgADCgcJBwAAAA==.Ferachio:BAAALgAECgQJBQAAAA==.',
Ff='Ffreshcope:BAAALgAFFAEJAQABLgAFFAQJCQARAM0VAA==.',
Fi='Fierysquish:BAAALgADCgUJBgAAAA==.Fightinmoose:BAAALgAECgQJBAAAAA==.Fireblitzer:BAAALgADCgEJAQAAAA==.Fistferge:BAAALgAECgUJBQABLgAECgcJGQAgABkgAA==.',
Fn='Fnaskmar:BAAALgAECgYJEQAAAA==.',
Fo='Fogpaw:BAAALgADCggJFQAAAA==.Foosaa:BAAALgAECgUJCAAAAA==.Forbearance:BAABLgAECn8eAAIgAAkJQx5ABADFAgAgAAkJQx5ABADFAgAAAA==.',
Fr='Franco:BAABLgAECn8XAAIEAAgJygzXEgBkAQAEAAgJygzXEgBkAQAAAA==.Freshfresh:BAAALgAECgUJBgABLgAFFAQJCQARAM0VAA==.Freshlock:BAACLgAFFH8JAAMRAAQJzRW2FgCwAAARAAIJORa2FgCwAAAWAAIJYRWABABcAAAuAAQKfxkABBYACQkxIj8MAP4BABYABQlcJT8MAP4BABEABgkzH2xOAN0BABAABAk/JMAJAKYBAAAA.Friend:BAAALgAECgEJAgAAAA==.Fright:BAABLgAECn8WAAIHAAgJcxJ+VQDhAQAHAAgJcxJ+VQDhAQAAAA==.Friska:BAAALgAECgEJAQAAAA==.Frostbolt:BAAALgAECgEJAQAAAA==.Frostcool:BAAALgAECgYJEQAAAA==.Frostyh:BAAALgAECgYJCQAAAA==.Frostyp:BAACLgAFFH8IAAIhAAMJswXcDADbAAAhAAMJswXcDADbAAAuAAQKfyAAAiEACQmeGSgOAKACACEACQmeGSgOAKACAAAA.',
Fu='Furion:BAABLgAECn8UAAIZAAYJjRTpTAByAQAZAAYJjRTpTAByAQAAAA==.Furiousbruja:BAAALgAECgMJBgAAAA==.',
Fy='Fyre:BAAALgAECgcJDAAAAA==.Fyrebird:BAAALgAECgMJAwABLgAECgcJDAAMAAAAAA==.',
Ga='Galadhriel:BAABLgAECn8bAAMDAAgJRRyMGgBmAgADAAgJRRyMGgBmAgAcAAEJVgMtjQAhAAAAAA==.Galadima:BAABLgAECn8fAAIbAAgJaRnRCAC4AQAbAAgJaRnRCAC4AQAAAA==.Galaxywing:BAAALgAECgMJBgAAAA==.Ganador:BAABLgAECn8WAAMRAAkJJBUYZwCWAQARAAcJ1xUYZwCWAQAWAAQJpAzgMAD2AAAAAA==.Gayguyender:BAAALgAECgUJCAAAAA==.',
Gb='Gbones:BAAALgADCgkJCQAAAA==.',
Ge='Geerah:BAAALgADCgYJBgAAAA==.Gennoro:BAAALgADCgcJBwABLgAECgYJEQAMAAAAAA==.',
Gl='Glizzies:BAABLgAECn8kAAIHAAgJXCMAAgCsAgAHAAgJXCMAAgCsAgAAAA==.Glocky:BAAALgADCgcJBwAAAA==.',
Gn='Gnomeofdeath:BAABLgAECn8YAAICAAgJjCHZFgDyAgACAAgJjCHZFgDyAgAAAA==.',
Go='Gokusan:BAAALgADCgYJBwABLgAECgcJGQARACYiAA==.Gomgar:BAAALgADCgcJEgAAAA==.Gooned:BAAALgAECgYJEwAAAA==.Goonforall:BAAALgADCgEJAQAAAA==.',
Gr='Grampus:BAAALgADCgIJAgABLgADCgYJBgAMAAAAAA==.Grashoppa:BAAALgAECgQJCQAAAA==.Greentide:BAABLgAECn8fAAIfAAgJxB6tDwCbAgAfAAgJxB6tDwCbAgAAAA==.Grengar:BAAALgAECgYJDgAAAA==.Groovybun:BAAALgADCgIJAgAAAA==.Groovymochi:BAABLgAECn8ZAAIiAAcJew5bCABzAQAiAAcJew5bCABzAQAAAA==.',
Gu='Guccimaybe:BAABLgAECn8bAAIjAAgJ6xDSDAD2AQAjAAgJ6xDSDAD2AQAAAA==.Guldaniel:BAAALgADCgEJAQAAAA==.Guldanramsey:BAAALgAECgcJEQAAAA==.Gunjá:BAAALgADCgYJCwAAAA==.',
Gw='Gwynastrasza:BAAALgAECgQJCQAAAA==.Gwynneth:BAAALgADCgcJDQAAAA==.',
Gx='Gxre:BAAALgAECgkJAgAAAA==.',
['Gò']='Gòku:BAABLgAECn8ZAAMRAAcJJiKiBAA1AgARAAYJJiKiBAA1AgAWAAIJvhFvTACIAAAAAA==.',
['Gö']='Göuf:BAAALgAECgcJBwAAAA==.',
['Gü']='Güy:BAAALgAECgYJBgAAAA==.',
Ha='Halea:BAABLgAECn8YAAINAAgJpRwsIwB/AgANAAgJpRwsIwB/AgAAAA==.Haleluya:BAAALgAECgYJBwABLgAECggJGAANAKUcAA==.Halepurr:BAAALgADCgIJAgABLgAECggJGAANAKUcAA==.Halogenrofl:BAABLgAECn8bAAIdAAgJgxj2AQAOAgAdAAgJgxj2AQAOAgAAAA==.Hammahtime:BAAALgADCgcJBwAAAA==.Hammerferge:BAABLgAECn8ZAAIgAAcJGSByAgDRAQAgAAcJGSByAgDRAQAAAA==.Handsofelune:BAAALgAECgQJBAAAAA==.Hannibol:BAAALgADCgYJCAAAAA==.Harrowhark:BAAALgAECgUJCQAAAA==.Hawktwua:BAAALgAECggJDAAAAA==.Hawtshot:BAAALgAECgQJBgAAAA==.Hazelena:BAAALgADCggJDQAAAA==.',
Hb='Hbz:BAABLgAECn8dAAIaAAgJgRj1DgAZAgAaAAgJgRj1DgAZAgAAAA==.',
He='Healingbrew:BAABLgAECn8YAAIUAAgJvBjcFgBRAgAUAAgJvBjcFgBRAgAAAA==.Healzplz:BAAALgADCgcJBwAAAA==.Heretoohelp:BAAALgAECgMJBgAAAA==.',
Hi='Hildar:BAAALgAECgcJDAAAAA==.Hillcoast:BAAALgADCgUJBQAAAA==.',
Ho='Holeymoley:BAAALgAECgEJAgAAAA==.Holibeef:BAAALgAECgUJBQABLgAECgYJEgAMAAAAAA==.Holybits:BAAALgAECggJEwAAAA==.Holylinoleum:BAAALgADCgQJBAABLgADCggJBgAMAAAAAA==.Holysquish:BAACLgAFFH8KAAIHAAQJ0AzjBABHAQAHAAQJ0AzjBABHAQAuAAQKfyQAAgcACQm4HjYeALYCAAcACQm4HjYeALYCAAAA.Holyz:BAABLgAECn8gAAIhAAgJ6ByZFgAzAgAhAAgJ6ByZFgAzAgAAAA==.Honeydip:BAABLgAECn8eAAIEAAkJVxYGGQByAgAEAAkJVxYGGQByAgAAAA==.Honésty:BAABLgAECn8UAAIYAAcJuxapGgAHAgAYAAcJuxapGgAHAgAAAA==.Hoontertile:BAAALgADCgcJBwAAAA==.Hotfistbaby:BAAALgAECgcJCgAAAA==.Hotspankyboi:BAABLgAECn8UAAIgAAgJRSbxAABjAwAgAAgJRSbxAABjAwAAAA==.',
Hr='Hruun:BAAALgADCgcJBwAAAA==.',
Hu='Huntskii:BAAALgAECgQJBQAAAA==.Hussle:BAAALgADCggJDgAAAA==.',
Ic='Iceicebabye:BAAALgAECgQJBwAAAA==.Iceleaf:BAAALgADCgYJBQAAAA==.Iciest:BAAALgAECgMJAgABLgAECggJJAAHAFwjAA==.',
Ig='Iger:BAAALgADCgcJDwAAAA==.',
Ih='Iha:BAAALgADCgIJAwAAAA==.',
Ij='Ijudgepeople:BAAALgADCggJCAABLgAECgIJAgAMAAAAAA==.',
Ik='Ikkaroas:BAAALgAECgUJBQAAAA==.Ikkis:BAAALgAECgQJCAAAAA==.Ikmoti:BAAALgAECgEJAQAAAA==.',
Il='Ileinaa:BAABLgAECn8vAAIYAAgJWRLtHwDiAQAYAAgJWRLtHwDiAQAAAA==.Iliketrains:BAABLgAECn8aAAIeAAgJ/xl8FgBmAgAeAAgJ/xl8FgBmAgAAAA==.Illuminatì:BAAALgAECgQJCQAAAA==.',
Im='Immortalhulk:BAAALgADCgIJAgAAAA==.',
In='Indicud:BAAALgAECgUJCQAAAA==.Inoxiakek:BAAALgAECgQJCAAAAA==.Intensedh:BAAALgAECgUJCQABLgAECgYJEwAMAAAAAA==.Intensevok:BAAALgADCgYJBgABLgAECgYJEwAMAAAAAA==.Intensifiedx:BAAALgAECgYJEwAAAA==.',
Is='Iscreamalot:BAABLgAECn8fAAIZAAgJAhkJGQCDAgAZAAgJAhkJGQCDAgAAAA==.Isele:BAAALgAECgQJBAABLgAECgYJCgAMAAAAAA==.',
It='Itybity:BAAALgAECgUJBQAAAA==.',
Iy='Iyatsuki:BAAALgAFFAIJAgAAAA==.',
Ja='Jawbone:BAAALgADCgEJAQAAAA==.Jayfizzle:BAAALgAECgEJAgAAAA==.Jaymazing:BAAALgAECgcJEQABLgAECgEJAgAMAAAAAA==.',
Ji='Jimmyboy:BAAALgADCgUJBQAAAA==.',
Jo='Joenormousgg:BAAALgADCgUJBQAAAA==.Johnathan:BAAALgADCgEJAQAAAA==.Johnconner:BAAALgAECgYJBgAAAA==.Jonald:BAAALgAECgIJAgABLgAECgcJGwAUAD0ZAA==.Jongwoo:BAAALgADCgYJCAAAAA==.Jonthecron:BAABLgAECn8bAAMUAAcJPRl0BwCEAQAUAAcJPRl0BwCEAQAkAAEJ1BE8egA2AAAAAA==.Joojekabab:BAAALgADCgEJAQAAAA==.Jorkinit:BAAALgAECggJEwAAAA==.Jormot:BAAALgAECgEJAQABLgAECgcJDAAMAAAAAA==.Jorok:BAABLgAECn8VAAIeAAkJhBXaHAAqAgAeAAkJhBXaHAAqAgAAAA==.',
Ju='Jubilee:BAABLgAECn8hAAIRAAkJFRnbIwCEAgARAAkJFRnbIwCEAgAAAA==.Jumannji:BAABLgAECn8WAAIeAAgJWRguFwBeAgAeAAgJWRguFwBeAgAAAA==.Jurik:BAAALgADCgQJCgAAAA==.Justadragon:BAAALgADCgEJAQAAAA==.',
Ka='Kabluey:BAAALgADCgEJAQAAAA==.Kalarm:BAAALgADCgYJBgAAAA==.Kallidan:BAABLgAECn8bAAINAAkJlBSIEACBAQANAAkJlBSIEACBAQAAAA==.Kallight:BAAALgADCgkJEQAAAA==.Karks:BAACLgAFFH8GAAMZAAMJSx0sCADBAAAZAAIJ6BssCADBAAAlAAEJEiDVCABjAAAuAAQKfx0AAxkACAkeIH8UAKoCABkACAkOG38UAKoCACUAAwneGKQfAPEAAAAA.Karsaørlong:BAAALgAECgEJAQAAAA==.Kassabekkaia:BAAALgADCggJDgABLgAECgYJDAAMAAAAAA==.Kazroth:BAAALgADCgcJDQAAAA==.',
Ke='Kelewan:BAABLgAECn8dAAMTAAgJcBWrFgCrAQATAAcJZBarFgCrAQACAAQJ8QvZ0gDbAAAAAA==.Kellabrimbor:BAAALgADCgUJBQAAAA==.Kellelor:BAAALgAECgEJAwAAAA==.Kerrigan:BAAALgAECgEJAQABLgAECgYJCAAMAAAAAA==.',
Ki='Killkillkill:BAAALgADCgkJGgAAAA==.Kindassuddy:BAABLgAECn8bAAIBAAgJCCCZKgDIAgABAAgJCCCZKgDIAgAAAA==.Kindled:BAABLgAECn8VAAIBAAgJlxa6awD+AQABAAgJlxa6awD+AQAAAA==.Kinvardar:BAAALgAECgYJDAAAAA==.Kirbbslav:BAAALgADCgEJAQABLgAFFAUJDwAbAG8VAA==.Kirbislav:BAAALgAECgYJDgABLgAFFAUJDwAbAG8VAA==.Kirbslav:BAACLgAFFH8PAAIbAAUJbxVPBACbAQAbAAUJbxVPBACbAQAuAAQKfyQAAhsACQmWI6cEACMDABsACQmWI6cEACMDAAAA.Kirbyslav:BAAALgADCgIJAwABLgAFFAUJDwAbAG8VAA==.Kirkland:BAAALgAECgIJAgAAAA==.Kirklandbeef:BAAALgAECgIJAgAAAA==.',
Kn='Kniavez:BAAALgAECgcJEgAAAA==.',
Ko='Koranova:BAAALgAECgYJDAAAAA==.Korro:BAABLgAECn8dAAIJAAgJDR0gBQC9AgAJAAgJDR0gBQC9AgAAAA==.Kostin:BAABLgAECn8fAAIZAAgJ/RdvHgBcAgAZAAgJ/RdvHgBcAgAAAA==.',
Kr='Krak:BAAALgAECgYJEAAAAA==.Krasta:BAAALgAECgMJBgAAAA==.Kratosdh:BAAALgADCgMJBAAAAA==.Krolow:BAACLgAFFH8PAAIZAAUJkhbkAgBOAQAZAAUJkhbkAgBOAQAuAAQKfx0AAxkACAnqG6UjADgCABkABwlOH6UjADgCABoAAglYB3A9AGIAAAAA.Kruugh:BAABLgAECn8UAAIeAAYJ0hWsNQB+AQAeAAYJ0hWsNQB+AQAAAA==.',
Ku='Kuler:BAABLgAECn8fAAIZAAgJ5x3hFACmAgAZAAgJ5x3hFACmAgAAAA==.Kungfushrub:BAAALgAECgYJDAAAAA==.Kuulandor:BAABLgAECn8lAAITAAkJOyGRAwAfAwATAAkJOyGRAwAfAwAAAA==.',
['Kè']='Kèèn:BAABLgAFFH8IAAIHAAMJwB2GDwAsAQAHAAMJwB2GDwAsAQAAAA==.',
['Ké']='Két:BAABLgAECn8ZAAIDAAgJzxoTJwAaAgADAAgJzxoTJwAaAgAAAA==.',
['Kê']='Kêt:BAAALgADCgMJAwABLgAECggJGQADAM8aAA==.',
['Kí']='Kítkat:BAAALgAECggJEwAAAA==.',
['Kÿ']='Kÿra:BAAALgAECgEJAQAAAA==.',
Le='Leesin:BAAALgADCgkJCQAAAA==.Levelground:BAAALgAECgUJCQAAAA==.Lewd:BAAALgAECgIJAwABLgAECggJGAANAKUcAA==.Leylines:BAAALgADCgcJBwAAAA==.',
Li='Liakä:BAAALgADCgYJBgAAAA==.Lightrampant:BAAALgADCgMJAQAAAA==.Lilmonkey:BAAALgADCgQJBgAAAA==.Limegreen:BAAALgADCgEJAQAAAA==.Liquidsevenz:BAABLgAECn8ZAAIjAAcJDhIZBAB2AQAjAAcJDhIZBAB2AQAAAA==.Litlit:BAAALgAECgYJBwAAAA==.',
Lo='Lodoss:BAABLgAECn8hAAIfAAgJ6hkzBAAxAgAfAAgJ6hkzBAAxAgAAAA==.Lollipops:BAAALgAECgEJAQABLgAECggJHQAHAGYaAA==.Lonah:BAAALgADCgkJEwABLgAECggJIwAHADElAA==.Lorienb:BAABLgAECn8dAAMhAAgJ9haHFwAoAgAhAAgJ9haHFwAoAgAXAAIJbRCNSQByAAAAAA==.Lotheran:BAAALgADCgEJAQAAAA==.Lothé:BAAALgAECgQJBAAAAA==.Lowkydead:BAAALgADCgEJAQAAAA==.',
Lu='Lubelesso:BAAALgADCgkJFgAAAA==.Luckehlock:BAACLgAFFH8LAAIQAAUJlyENAAAIAgAQAAUJlyENAAAIAgAuAAQKfyAAAxAACQlwJAsAAN4DABAACQlwJAsAAN4DABEAAQlvAIg0ARIAAAAA.Luckehtwo:BAAALgADCgIJAgABLgAFFAUJCwAQAJchAA==.Luxcn:BAAALgAECggJDgAAAA==.',
Ma='Macgibbins:BAAALgAECggJEQAAAA==.Madepure:BAAALgAECgMJAwABLgAECggJJAAHAFwjAA==.Magus:BAAALgAFFAEJAQABLgAFFAYJEAAcAOMaAA==.Mahyora:BAAALgAECgEJBAAAAA==.Mavus:BAAALgAECgYJEAAAAA==.',
Me='Melylen:BAAALgAECgQJCAAAAA==.',
Mi='Milkbolt:BAAALgAECgYJEQAAAA==.Milkhoundttv:BAAALgAECgYJEgAAAA==.Minigolf:BAABLgAECn8fAAMNAAgJwRb7EQByAQANAAgJCRb7EQByAQAdAAUJWRnFMABLAQAAAA==.Minigun:BAAALgAECgYJDAAAAA==.Minioozy:BAAALgADCgUJBQAAAA==.Minivan:BAAALgADCgQJBAABLgAECggJHwANAMEWAA==.Misawa:BAAALgAECgYJBgAAAA==.Mizuboxx:BAABLgAECn8aAAIbAAcJoCLsAQCPAgAbAAcJoCLsAQCPAgAAAA==.',
Mo='Molyver:BAABLgAECn8cAAMkAAkJ2RZOJgClAQAkAAcJ0RJOJgClAQAiAAUJcwvlFwBvAAAAAA==.Momak:BAAALgAECgQJBAABLgAECgYJCQAMAAAAAA==.Mommey:BAAALgAECgQJBAAAAA==.Moonfrost:BAAALgADCgYJBwAAAA==.Moonkitty:BAAALgADCgEJAQAAAA==.Moonmane:BAAALgAECgYJDAAAAA==.Moonmellow:BAAALgAECgYJBwAAAA==.Moosin:BAAALgAECgEJAQAAAA==.Mozgus:BAABLgAECn8UAAIYAAYJUSEREwBHAgAYAAYJUSEREwBHAgAAAA==.',
Mu='Munder:BAAALgAECgQJBgAAAA==.Murdurio:BAAALgAECgQJCwAAAA==.Musculate:BAAALgAECgQJEAAAAA==.',
Mx='Mxdi:BAABLgAECn8eAAQDAAgJPyPYAQC7AgADAAgJPyPYAQC7AgAcAAEJ9BLceQA+AAAIAAEJzQ3fNgArAAAAAA==.',
Na='Nazdarok:BAAALgAECgMJBAAAAA==.Nazenoth:BAAALgADCgUJCwAAAA==.Nazgûl:BAABLgAECn8WAAISAAYJgB90CADzAQASAAYJgB90CADzAQAAAA==.',
Ne='Necrofearlia:BAAALgAECgYJDwAAAA==.Nensha:BAAALgAECgUJCQAAAA==.Nethys:BAABLgAECn8kAAMhAAkJ8BsIAQCUAgAhAAkJ8BsIAQCUAgAXAAEJnAX5XAAoAAAAAA==.',
Ni='Nick:BAACLgAFFH8QAAIcAAYJ4xrfAACeAQAcAAYJ4xrfAACeAQAuAAQKfygABBwACQkeJFoCAJwDABwACQkeJFoCAJwDACYABgmmIFQIACgCAAMAAQnBCOvHADoAAAAA.Nightxangel:BAAALgADCgcJBwAAAA==.',
No='Noctrimm:BAAALgADCgEJAQAAAA==.Nolyt:BAABLgAECn8UAAICAAcJGAm6GwA6AQACAAcJGAm6GwA6AQAAAA==.Nonna:BAABLgAECn8dAAIlAAgJkB16AQD/AQAlAAgJkB16AQD/AQAAAA==.Noolore:BAACLgAFFH8NAAICAAQJ0BiWBABsAQACAAQJ0BiWBABsAQAuAAQKfyUAAgIACQkdIVsXAO8CAAIACQkdIVsXAO8CAAAA.Norandil:BAAALgAECgEJAgAAAA==.Notendela:BAAALgAECgEJAQABLgAECgYJCgAMAAAAAA==.',
Nu='Nuiria:BAAALgADCgUJBQAAAA==.Nurfgun:BAABLgAECn8bAAMEAAcJXCHYAwBKAgAEAAcJ9h/YAwBKAgAFAAYJ/yLjHQA1AgAAAA==.Nurfroll:BAAALgADCgEJAQABLgAECgcJGwAEAFwhAA==.Nurfstrasza:BAAALgADCgYJBgABLgAECgcJGwAEAFwhAA==.',
Nw='Nwahher:BAAALgADCgUJBwAAAA==.',
Of='Offleash:BAAALgADCggJBwAAAA==.',
On='Onlyfrost:BAAALgADCgcJCQAAAA==.Onlyslams:BAABLgAECn8dAAIUAAgJ4RspFwBNAgAUAAgJ4RspFwBNAgABLgAECggJHAADAMIaAA==.',
Op='Opheliana:BAAALgADCgEJAQAAAA==.',
Or='Orcsmash:BAAALgAECgQJCQAAAA==.',
Ow='Owlwithahat:BAAALgADCgcJDQAAAA==.',
Ox='Oxen:BAABLgAECn8fAAQTAAgJ+R/YCQB+AgATAAgJ5x7YCQB+AgACAAcJoRlUDwCdAQAnAAEJbw0RFwA0AAAAAA==.',
Pa='Padraig:BAAALgADCgcJBwAAAA==.Passoot:BAAALgAECgEJBgAAAA==.',
Pe='Pega:BAAALgADCgQJBAABLgAECggJJQAjAFciAA==.Pegah:BAAALgAECgMJAwAAAA==.Pege:BAABLgAECn8lAAIjAAgJVyKwAAByAgAjAAgJVyKwAAByAgAAAA==.Penniee:BAAALgAECgMJBAAAAA==.Penniwing:BAABLgAECn8jAAQOAAgJ8xsCHADoAQAOAAcJgxoCHADoAQAGAAgJUwsZHgCRAQAPAAEJ0hKaQAAvAAAAAA==.Percival:BAECLgAFFH8SAAIJAAYJ2x4VAADyAQAJAAYJ2x4VAADyAQAuAAQKfyAABAkACQlcI0EAAMQDAAkACQlcI0EAAMQDAAUABQnNHOJMAB0BAAQAAwmVI/SdAJQAAAAA.',
Ph='Phaedra:BAAALgAECgkJKAAAAQ==.Phanuel:BAAALgAECgYJEQABLgAFFAMJCAAHAMAdAA==.Phealvoker:BAAALgADCgIJAgABLgAECgcJGQAeAJgdAA==.',
Pi='Piffboy:BAAALgAECggJDgAAAA==.Pissvibe:BAAALgAECgcJBwAAAA==.Pixr:BAAALgAECgcJAQAAAA==.',
Po='Powrwordaddy:BAAALgADCggJDgABLgAECgYJDAAMAAAAAA==.',
Pr='Priestler:BAABLgAECn8fAAQXAAgJ4x5oCQCkAgAXAAgJ4x5oCQCkAgAhAAcJgxq/HAD1AQAYAAQJFQUjHQA/AAAAAA==.Primeape:BAAALgAECgYJDgAAAA==.Prodigal:BAAALgADCgUJBQAAAA==.',
Pu='Pullbarg:BAAALgAECgEJAgAAAA==.Pumpies:BAAALgAECgUJDgAAAA==.Punchdrunk:BAAALgADCgYJDQAAAA==.Purrdruid:BAAALgADCgUJBQAAAA==.',
Py='Pyru:BAAALgADCgYJBgAAAA==.',
['Pà']='Pàngde:BAAALgAECgIJAgAAAA==.',
['Pï']='Pïng:BAABLgAECn8WAAIEAAYJVxHzVABpAQAEAAYJVxHzVABpAQAAAA==.',
Qu='Quickkwinter:BAAALgAECgEJAQAAAA==.Quickly:BAAALgAECgQJBAAAAA==.',
Ra='Raantoks:BAAALgADCggJCgAAAA==.Rachet:BAAALgAECgMJBwAAAA==.Raelilblack:BAAALgAECgYJBwAAAA==.Rakhár:BAAALgADCgcJBwABLgAECgYJGgAUANkbAA==.Raner:BAAALgADCgMJAwABLgAECgcJHwAkAOscAA==.Rashala:BAAALgAECgQJDAAAAA==.Raucahann:BAAALgAECgEJAQAAAA==.Rayado:BAAALgAECgQJBwAAAA==.Razarke:BAABLgAECn8XAAIPAAcJXCMQBQCxAgAPAAcJXCMQBQCxAgAAAA==.',
Re='Reggienoble:BAACLgAFFH8FAAIJAAIJWRuOAwC8AAAJAAIJWRuOAwC8AAAuAAQKfx4AAgkACAkWJHcCABcDAAkACAkWJHcCABcDAAAA.Rekerî:BAAALgAECgYJBgAAAA==.Reverendmini:BAAALgAECgMJAwAAAA==.Reynaria:BAABLgAECn8ZAAMiAAgJACAqCQDBAgAiAAgJACAqCQDBAgAkAAMJihpPSQDuAAAAAA==.Reyyne:BAACLgAFFH8HAAIbAAMJVB0TBgD2AAAbAAMJVB0TBgD2AAAuAAQKfyYAAhsACAmtIhMJAN8CABsACAmtIhMJAN8CAAAA.',
Ri='Richmage:BAAALgAECgMJBAABLgAFFAQJCwAFAEgdAA==.Rimetail:BAAALgAECgYJBgAAAA==.Rinzee:BAAALgAECgQJBgAAAA==.Rinzlrr:BAAALgAECgUJCAABLgAECgcJHwAkAOscAA==.Rioroute:BAAALgADCggJDgAAAA==.Rivett:BAAALgADCgUJBQAAAA==.',
Ro='Roelson:BAAALgADCgEJAQAAAA==.Roflock:BAAALgADCgEJAQAAAA==.Rohrn:BAABLgAECn8XAAIHAAYJ8xQCHwA1AQAHAAYJ8xQCHwA1AQAAAA==.Rol:BAACLgAFFH8GAAIXAAMJJRPYBgDgAAAXAAMJJRPYBgDgAAAuAAQKfxcABBgACAndHmEKAKcCABgACAn8HWEKAKcCABcABAlUFwwwAB8BACEAAwkjHUpBAO4AAAAA.Rolius:BAAALgADCgQJBAAAAA==.Rolonar:BAAALgADCgEJAQAAAA==.Rosenylund:BAAALgAECgYJEgAAAA==.Rotfist:BAAALgADCgUJBQAAAA==.',
Ry='Rydia:BAAALgADCgQJBAAAAA==.',
Sa='Safa:BAAALgAECgYJCgABLgAECggJGgABALkbAA==.Saintsnetie:BAAALgAECgQJCAAAAA==.',
Sc='Scottyknows:BAAALgADCgYJBgAAAA==.Scottymaybe:BAAALgAECgYJBgAAAA==.Scredwin:BAABLgAECn8ZAAMWAAgJhhUhCABCAgAWAAgJhhUhCABCAgARAAEJOQN0KQEoAAABLgAECgkJJQAhAIYOAA==.',
Se='Senorbobo:BAABLgAECn8kAAIaAAgJDx4RAgANAgAaAAgJDx4RAgANAgAAAA==.Serenian:BAAALgAECgQJBQAAAA==.Serni:BAAALgAECgIJAgAAAA==.',
Sh='Shadora:BAAALgAECgYJDwAAAA==.Shadowsbane:BAAALgADCgUJBQAAAA==.Shadowslite:BAAALgAECgEJAQAAAA==.Shadowwolf:BAABLgAECn8dAAIDAAcJIxADFQAdAQADAAcJIxADFQAdAQAAAA==.Sham:BAABLgAECn8pAAMRAAgJ8iDlAQCcAgARAAgJ8iDlAQCcAgAWAAIJ5A9cWABlAAAAAA==.Shamios:BAABLgAECn8YAAIDAAgJ5CCEEQCqAgADAAgJ5CCEEQCqAgAAAA==.Shammknight:BAAALgADCgQJBAAAAA==.Shanksinatrá:BAACLgAFFH8RAAMKAAYJtxopAgDiAQAKAAUJahspAgDiAQALAAIJORhFAQDNAAAuAAQKfycAAwoACQljJnUBAK4DAAoACQlSJnUBAK4DAAsAAwmqGncPABkBAAAA.Shaquira:BAAALgAECgYJBwAAAA==.Shatt:BAAALgAECgYJBgAAAA==.Shaxxi:BAAALgAECgYJEQAAAA==.Shedari:BAAALgADCgkJEgAAAA==.Shephrah:BAABLgAECn8dAAMiAAgJRwtRKgBlAQAiAAgJRwtRKgBlAQAUAAMJRAU+GQB/AAAAAA==.Shiftalic:BAAALgAECgcJDQAAAA==.Shifter:BAAALgAECgYJEAAAAA==.Shoshanna:BAAALgAECgIJAgAAAA==.Shourioom:BAABLgAECn8jAAIHAAgJMSVNCABRAwAHAAgJMSVNCABRAwAAAA==.Shourix:BAABLgAECn8cAAIZAAcJriEjEwC2AgAZAAcJriEjEwC2AgABLgAECggJIwAHADElAA==.Shploople:BAAALgAECgQJBgAAAA==.Shuckle:BAAALgAECgQJBAABLgAFFAYJEAAcAOMaAA==.Shuppet:BAAALgADCgUJDAAAAA==.',
Si='Sifuicyhot:BAAALgAECgYJDAAAAA==.Sihnn:BAAALgAECgYJBgAAAA==.Simzerker:BAACLgAFFH8NAAIZAAUJVCNcAQD0AQAZAAUJVCNcAQD0AQAuAAQKfxsAAhkACAmHIloHADMDABkACAmHIloHADMDAAAA.',
Sk='Skwinkles:BAAALgADCgEJAQAAAA==.',
Sl='Slambulance:BAAALgADCgIJAgAAAA==.Sleepington:BAAALgAECgMJAwAAAA==.Slickrick:BAAALgAECgMJBAAAAA==.Slikshotgrey:BAAALgADCgQJBAAAAA==.Slyvex:BAAALgADCgYJCgAAAA==.',
Sm='Smûsh:BAAALgADCgIJAgAAAA==.',
Sn='Snackum:BAAALgADCgYJBgAAAA==.Snarfca:BAAALgAECgQJBAAAAA==.Sneakthief:BAAALgADCgYJBwAAAA==.Sniiffle:BAABLgAECn8ZAAIDAAcJCBslJwAaAgADAAcJCBslJwAaAgAAAA==.Snowmage:BAABLgAECn8gAAMVAAgJLR9XAQDKAgAVAAgJLR9XAQDKAgAoAAEJugfOEAAwAAAAAA==.',
So='Soarscha:BAAALgAECgEJAQAAAA==.Softly:BAACLgAFFH8LAAIiAAYJOxXaAQARAgAiAAYJOxXaAQARAgAuAAQKfykAAiIACQk+JjkAAOkDACIACQk+JjkAAOkDAAAA.Sokan:BAAALgADCgUJBwAAAA==.Somecutty:BAAALgADCgEJAQAAAA==.',
Sp='Spellbeard:BAAALgADCggJBwAAAA==.Spellcrackle:BAAALgADCgcJDwABLgAECgYJEgAMAAAAAA==.Sploosh:BAAALgADCgEJAQAAAA==.Spùd:BAAALgAECgEJAQAAAA==.',
Sq='Squa:BAABLgAECn8bAAMKAAgJpiKhCgDoAgAKAAgJpiKhCgDoAgALAAQJchx3DABcAQAAAA==.Squishdemon:BAAALgADCgEJAQAAAA==.',
Ss='Ssudds:BAAALgAECgYJCgABLgAECggJGwABAAggAA==.Ssuddychan:BAAALgAECggJEgABLgAECggJGwABAAggAA==.',
St='Stalagstrype:BAAALgAECgYJDAAAAA==.Stankfu:BAAALgADCgQJBAAAAA==.Starkisses:BAABLgAECn8dAAIEAAkJ9xs6DwDBAgAEAAkJ9xs6DwDBAgAAAA==.Stenkeydk:BAABLgAECn8bAAICAAgJyhJTUgD6AQACAAgJyhJTUgD6AQAAAA==.Steve:BAAALgAECgQJBAABLgAECgIJAgAMAAAAAA==.Stonepaw:BAAALgADCgMJAwAAAA==.Storebrand:BAAALgADCgcJCAABLgAECgIJAgAMAAAAAA==.Storebrandps:BAAALgADCgYJBwABLgAECgIJAgAMAAAAAA==.Stratego:BAAALgADCgQJCgAAAA==.Styrthe:BAACLgAFFH8TAAMUAAYJtRouBQCCAQAUAAUJzRcuBQCCAQAiAAIJJxZjCgBeAAAuAAQKfyAAAxQACQmDGfMRAIUCABQACQmDGfMRAIUCACIABwlFEB4uAEoBAAAA.',
Su='Subotae:BAAALgADCgMJAwAAAA==.Surfacing:BAAALgAECgcJDQAAAA==.Surventval:BAAALgAECgYJCwABLgAECgcJHwAkAOscAA==.',
Sw='Swindler:BAAALgAFFAEJAgAAAA==.Swollstone:BAAALgAECgYJDgAAAA==.',
Sy='Symphony:BAABLgAECn8bAAINAAgJwRzyHACkAgANAAgJwRzyHACkAgAAAA==.Syzegy:BAAALgAECgEJAwAAAA==.',
Ta='Taeka:BAAALgAECgQJBAAAAA==.Talkimas:BAABLgAECn8dAAMFAAgJNBpiGwBKAgAFAAgJNBpiGwBKAgAEAAEJAAAbwQBDAAAAAA==.Talvisota:BAABLgAECn8cAAICAAcJoBv5CgDQAQACAAcJoBv5CgDQAQAAAA==.Tankthor:BAABLgAECn8bAAMZAAgJSguXOQDAAQAZAAgJtwqXOQDAAQAaAAcJcgnmIgAnAQAAAA==.Tarirn:BAACLgAFFH8FAAICAAIJRxIlPQCkAAACAAIJRxIlPQCkAAAuAAQKfxQAAgIACAl+G4RSAPoBAAIACAl+G4RSAPoBAAAA.Tazgrim:BAAALgAECgYJDwAAAA==.',
Te='Teflondon:BAAALgADCgQJBwAAAA==.Tekos:BAAALgAECgQJBAABLgAFFAQJBwAdAP4RAA==.Tekoslul:BAACLgAFFH8HAAIdAAQJ/hHlAQADAQAdAAQJ/hHlAQADAQAuAAQKfxkAAx0ACQkBJC8CAHQDAB0ACQkBJC8CAHQDAA0ABAmXFi6PAAIBAAAA.Tekosp:BAAALgAECgMJBAABLgAFFAQJBwAdAP4RAA==.Tekosxd:BAAALgAECgEJAwABLgAFFAQJBwAdAP4RAA==.Telawolf:BAAALgADCggJCAAAAA==.Teldrussy:BAAALgADCgcJBwABLgAECggJFgAGAKMWAA==.Telorian:BAABLgAECn8aAAINAAgJpx7qJAB1AgANAAgJpx7qJAB1AgAAAA==.Tendeda:BAAALgAECgQJBAAAAA==.Terrasite:BAAALgAECgQJBAAAAA==.',
Th='Thalunar:BAAALgAFFAEJAQAAAA==.Thanatosmors:BAAALgAFFAEJAQAAAA==.Thatonedruid:BAAALgADCgUJBQABLgAECggJJAAaAA8eAA==.Thejw:BAAALgAECgUJDAAAAA==.Thrdeyethump:BAAALgAECgYJCQAAAA==.Thörck:BAAALgAECgQJBQAAAA==.',
Ti='Tigersu:BAAALgAFFAEJAQAAAA==.Tinklewinkle:BAABLgAECn8fAAIVAAgJiyKEAAAuAwAVAAgJiyKEAAAuAwAAAA==.Titanrb:BAAALgADCgcJCwAAAA==.',
Tj='Tjaili:BAAALgAECgcJDgAAAA==.',
To='Tocks:BAAALgAECgQJBQAAAA==.Toge:BAABLgAECn8VAAMBAAgJjSEyOQCRAgABAAgJjSEyOQCRAgAVAAEJ9AzwHgAzAAABLgAFFAUJDAAeAHQVAA==.Tokapolo:BAABLgAECn8YAAIeAAYJoyCqHgAaAgAeAAYJoyCqHgAaAgAAAA==.Topshelfelf:BAABLgAECn8eAAMXAAgJXxG9GADVAQAXAAgJXxG9GADVAQAYAAEJnwOBiAAnAAAAAA==.Torver:BAAALgAECgcJDwAAAA==.Totemsquish:BAAALgADCgEJAQAAAA==.',
Tr='Treemother:BAABLgAECn8cAAIDAAYJRRwBMwDdAQADAAYJRRwBMwDdAQAAAA==.Treewa:BAAALgAECgMJAwAAAA==.Tresdin:BAABLgAECn8UAAIHAAgJ/RZ7QAAkAgAHAAgJ/RZ7QAAkAgAAAA==.',
Ts='Tsohg:BAAALgADCgYJBQAAAA==.',
Tu='Tuhalla:BAABLgAECn8aAAIHAAgJUAuDIgAhAQAHAAgJUAuDIgAhAQAAAA==.Tumlock:BAABLgAECn8aAAMRAAYJfgxSlgAsAQARAAYJVQpSlgAsAQAWAAMJJAuECwBoAAAAAA==.Turbulence:BAAALgAECgQJBAAAAA==.',
Tw='Twl:BAAALgAECgQJBQAAAA==.',
['Tï']='Tïgra:BAABLgAECn8dAAINAAgJQx09IgCEAgANAAgJQx09IgCEAgAAAA==.',
Ua='Uandikillhim:BAABLgAECn8aAAIXAAgJNR0lCAC9AgAXAAgJNR0lCAC9AgAAAA==.',
Ul='Uldren:BAAALgAECgIJAgABLgAECgkJKQAKABIdAA==.',
Un='Uncompetent:BAAALgADCgEJAQAAAA==.Undeadbones:BAAALgAECgQJBwAAAA==.Unfading:BAABLgAECn8dAAIHAAgJPhumKgB6AgAHAAgJPhumKgB6AgAAAA==.Unholyknight:BAAALgADCgkJDgAAAA==.Uninfluenced:BAAALgAECgQJBAAAAA==.',
Ur='Uranus:BAABLgAECn8UAAIEAAYJHRnvYgA+AQAEAAYJHRnvYgA+AQAAAA==.Urban:BAAALgADCgEJAQAAAA==.Urtark:BAABLgAECn8fAAIZAAgJpRwsHQBkAgAZAAgJpRwsHQBkAgAAAA==.',
Va='Vadym:BAAALgAECgIJAgAAAA==.Vaelia:BAAALgAECgcJDAAAAA==.Vainquish:BAAALgAECgMJBAAAAA==.Valeriann:BAAALgADCgMJAwAAAA==.Valorias:BAABLgAECn8XAAIXAAgJlhnmDABqAgAXAAgJlhnmDABqAgAAAA==.Vankwish:BAABLgAECn8XAAMVAAcJixTWBwB/AQABAAcJdROVkgCuAQAVAAYJFxTWBwB/AQAAAA==.Varalic:BAAALgAECgIJAgABLgAECgcJDQAMAAAAAA==.Varandra:BAAALgADCgMJAwABLgAECgIJAgAMAAAAAA==.Vaulken:BAAALgAECgcJDQAAAA==.Vañquish:BAAALgADCgEJAQAAAA==.',
Ve='Veggyfruit:BAAALgAECgYJEgAAAA==.Ventrois:BAABLgAECn8fAAIkAAcJ6xxfBgB/AQAkAAcJ6xxfBgB/AQAAAA==.Verdarts:BAAALgADCgcJBwAAAA==.Veregas:BAAALgAECgYJEQAAAA==.Vermilion:BAAALgADCgYJCwAAAA==.Vesseven:BAACLgAFFH8FAAIZAAIJsRuUCAC6AAAZAAIJsRuUCAC6AAAuAAQKfx4AAhkACAlXHv8XAIwCABkACAlXHv8XAIwCAAAA.',
Vi='Vilienar:BAAALgAECgIJAgAAAA==.Vimao:BAAALgADCgUJCQAAAA==.Vizzy:BAAALgADCgcJBwAAAA==.',
Vo='Voidalic:BAACLgAFFH8PAAINAAUJVh2SBgC6AQANAAUJVh2SBgC6AQAuAAQKfxcAAg0ACAkJIywUAN8CAA0ACAkJIywUAN8CAAAA.Voidrend:BAACLgAFFH8PAAMNAAYJuhOPAQCnAQANAAYJuhOPAQCnAQASAAEJAAD+BQA2AAAuAAQKfycAAg0ACQncIBgJAD8DAA0ACQncIBgJAD8DAAAA.Voimasta:BAAALgADCgIJAgAAAA==.',
Vu='Vuloolu:BAAALgAECgYJDAAAAA==.Vulpiena:BAAALgADCgcJBwAAAA==.Vulvaenjoyer:BAAALgAECgYJBgAAAA==.',
['Vî']='Vî:BAAALgAECgYJDAAAAA==.Vîews:BAAALgAECggJEwAAAA==.',
['Vø']='Vøgue:BAABLgAECn8eAAILAAkJiBK3BQArAgALAAkJiBK3BQArAgAAAA==.',
Wa='Warbidet:BAAALgAECgEJAQAAAA==.Warlockwally:BAAALgAECgQJBAAAAA==.Warloko:BAAALgAECgYJDQAAAA==.Warmason:BAABLgAECn8cAAIaAAcJCxOoBgAyAQAaAAcJCxOoBgAyAQAAAA==.Warpheal:BAAALgADCgkJCgABLgAECgcJGQAeAJgdAA==.Warrida:BAAALgADCgEJAQAAAA==.Washed:BAAALgAECgYJEAAAAA==.',
We='Wealthy:BAABLgAECn8bAAMXAAgJ1heBFQD7AQAXAAgJhxOBFQD7AQAYAAYJOBf/LgCHAQAAAA==.Wearp:BAAALgADCgQJBAAAAA==.Weßall:BAAALgADCgcJBwAAAA==.',
Wh='Whiskeydix:BAAALgADCgYJBgAAAA==.Whyisitdark:BAAALgADCgUJBQAAAA==.',
Wi='Wiiska:BAAALgAECgYJBgAAAA==.Wildassassjd:BAAALgADCgUJBQABLgAECgQJBAAMAAAAAA==.',
Wo='Wonderful:BAAALgADCgMJAwAAAA==.',
Wr='Wrakk:BAABLgAECn8eAAIKAAgJxxI3BQCnAQAKAAgJxxI3BQCnAQAAAA==.Wrred:BAAALgAECgQJBwAAAA==.',
Xo='Xombi:BAAALgADCgQJBAABLgAECgYJCAAMAAAAAA==.',
Xt='Xtik:BAAALgADCgUJBQAAAA==.',
Ye='Yeahbuddy:BAAALgADCgQJBAAAAA==.',
Yu='Yunai:BAAALgAECgEJAQAAAA==.',
Ze='Zemi:BAABLgAECn8eAAIjAAkJxxKuCQA6AgAjAAkJxxKuCQA6AgAAAA==.Zeneragor:BAAALgAECgQJBAAAAA==.Zevalia:BAAALgAECgYJEQAAAA==.Zevarya:BAAALgADCgEJAQABLgAECgYJEQAMAAAAAA==.Zevelyon:BAAALgADCgEJAQABLgAECgYJEQAMAAAAAA==.',
Zo='Zophia:BAAALgAECgEJAQAAAA==.Zorak:BAAALgAECgIJAgABLgAFFAMJBwAbAFQdAA==.',
Zt='Ztoned:BAAALgADCgUJBgAAAA==.',
Zu='Zubby:BAABLgAECn8WAAIRAAYJDyA8XwCrAQARAAYJDyA8XwCrAQAAAA==.Zuddy:BAAALgADCgUJBQAAAA==.Zugrotic:BAAALgAECgYJCQAAAA==.Zulakunda:BAAALgAECgYJDgAAAA==.Zummey:BAAALgADCgcJBAAAAA==.',
Zy='Zylox:BAAALgAECgYJDAAAAA==.',
['Zë']='Zëüs:BAAALgAECgYJDQAAAA==.',
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
