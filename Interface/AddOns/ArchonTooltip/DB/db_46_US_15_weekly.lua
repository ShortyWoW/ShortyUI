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

local lookup = {'Warlock-Destruction','Warlock-Demonology','Mage-Frost','Paladin-Retribution','DemonHunter-Vengeance','Unknown-Unknown','Paladin-Holy','Shaman-Restoration','Hunter-Marksmanship','Hunter-Survival','Hunter-BeastMastery','DeathKnight-Unholy','Warrior-Fury','Evoker-Devastation','Priest-Holy','DemonHunter-Devourer','Rogue-Subtlety','Warrior-Arms','Druid-Restoration','DeathKnight-Blood','DeathKnight-Frost','Monk-Windwalker','Monk-Brewmaster','Paladin-Protection','Priest-Discipline','Evoker-Augmentation','Evoker-Preservation','Warrior-Protection','Shaman-Elemental','Rogue-Outlaw','Warlock-Affliction','Druid-Feral','Druid-Guardian','Monk-Mistweaver','Shaman-Enhancement','Priest-Shadow','DemonHunter-Havoc',}
local provider = {region='US',realm='Anvilmar',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aaril:BAAALgAECgEJAQAAAQ==.',
Ad='Adel:BAAALgADCgUJBQAAAA==.',
Ae='Aelitha:BAABLgAECn8ZAAMBAAYJ/QV2OQDOAAACAAYJsAQRYADTAAABAAYJtgR2OQDOAAAAAA==.',
Ak='Akaishi:BAAALgADCgIJAgAAAA==.Akali:BAAALgAFFAEJAQAAAA==.Akina:BAAALgADCgMJAQABLgAECggJFgADAIwKAA==.',
Al='Alathiana:BAAALgADCgUJCAAAAA==.Alcweaver:BAAALgAECgYJDQAAAA==.Alecto:BAAALgAECgMJAwAAAA==.Alindia:BAAALgAECgQJCgABLgAECggJFgADAIwKAA==.Alirrayia:BAAALgAECgQJBAAAAA==.Alirrayiia:BAACLgAFFH8FAAIEAAMJNQG6KwCwAAAEAAMJNQG6KwCwAAAuAAQKfyAAAgQACQlUDytNAPsBAAQACQlUDytNAPsBAAAA.Alkri:BAAALgADCgMJAwAAAA==.Allari:BAAALgAECgYJEwAAAA==.Allystar:BAAALgAECgEJAQAAAA==.Altheia:BAAALgAECgQJBAAAAA==.Alvidor:BAABLgAECn8bAAIDAAgJMQKygADTAAADAAgJMQKygADTAAAAAA==.',
Am='Ameria:BAAALgADCgUJBQAAAA==.',
An='Anastos:BAAALgAECgUJBQAAAA==.Andydufresne:BAAALgAECgQJBAABLgAECggJKgAFAIYlAA==.Angryqueer:BAAALgADCgEJAQAAAA==.',
Ao='Aowl:BAAALgAECgcJCwAAAA==.',
Ap='Apocketheory:BAAALgADCgIJAgAAAA==.Apolloerosb:BAAALgADCggJDgABLgAECgUJCgAGAAAAAA==.Apollossham:BAAALgAECgUJCgAAAA==.',
Ar='Arkanaun:BAABLgAECn8ZAAMHAAYJCxW7IQA4AQAHAAUJMhS7IQA4AQAEAAYJRBdlSAAwAQAAAA==.',
As='Ashes:BAAALgAECgcJAQAAAA==.Ashrán:BAAALgAECgYJCAAAAA==.Ashyluna:BAAALgAECgQJBAAAAA==.Astianna:BAAALgADCgMJAwAAAA==.',
Au='Aurinia:BAAALgADCgQJAgAAAA==.Aurore:BAAALgADCgQJBgAAAA==.',
Av='Avradea:BAAALgADCgEJAQABLgAECggJFgADAIwKAA==.',
Az='Azareth:BAAALgADCggJCAAAAA==.',
Ba='Baconatorr:BAAALgAECgMJAwAAAA==.Bagelbags:BAAALgADCgEJAQAAAA==.Bahler:BAAALgADCgUJBQABLgAECgMJAwAGAAAAAA==.Baji:BAABLgAECn8mAAIIAAgJciPmAQAWAwAIAAgJciPmAQAWAwAAAA==.Baklan:BAAALgAECgMJAwAAAA==.Barefaall:BAACLgAFFH8GAAIJAAQJGxE/GwCqAAAJAAQJGxE/GwCqAAAuAAQKfykAAgkACQl8G48LAO0CAAkACQl8G48LAO0CAAAA.Barefall:BAAALgAFFAEJAQABLgAFFAQJBgAJABsRAA==.Barefalls:BAABLgAECn8jAAMKAAgJlhywAwBaAgAKAAgJlhywAwBaAgAJAAEJjAGQlgAiAAABLgAFFAQJBgAJABsRAA==.Barelywolf:BAAALgAECgYJEwABLgAFFAEJAQAGAAAAAA==.Bashira:BAABLgAECn8VAAILAAcJsgnBMgBGAQALAAcJsgnBMgBGAQAAAA==.Bast:BAABLgAECn8XAAIMAAYJ8xKLQQA5AQAMAAYJ8xKLQQA5AQAAAA==.',
Be='Bearophe:BAAALgAECgEJAgAAAA==.Beerfist:BAAALgAECgEJAQAAAA==.Bellock:BAAALgADCggJCAAAAA==.Benisbagina:BAAALgADCggJCQAAAA==.Bergonator:BAABLgAECn8gAAINAAYJchBrIAAyAQANAAYJchBrIAAyAQAAAA==.Berrodiah:BAAALgAECgIJAgABLgAECggJFgAOALUYAA==.Bettyswalls:BAAALgAECgMJAwAAAA==.Beyarago:BAAALgAECgUJCQAAAA==.',
Bh='Bheiroth:BAABLgAECn8fAAIPAAcJvCP9AwCaAgAPAAcJvCP9AwCaAgAAAA==.',
Bl='Bladeygaga:BAABLgAECn8eAAIQAAgJrBv7CgAtAgAQAAgJrBv7CgAtAgAAAA==.Blasé:BAAALgAECgcJAQAAAA==.Blazingblood:BAAALgADCgUJAQAAAA==.Bloodknight:BAAALgADCgYJCQAAAA==.Bluett:BAAALgADCgkJFAAAAA==.Bláckøut:BAAALgADCgYJDAAAAA==.',
Bo='Bodhi:BAABLgAECn8WAAIRAAcJNhAIJwDAAQARAAcJNhAIJwDAAQAAAA==.Bogertus:BAACLgAFFH8GAAINAAMJCSPpCgA9AQANAAMJCSPpCgA9AQAuAAQKfycAAw0ABwm6JaAEAHcCAA0ABwm6JaAEAHcCABIAAgn1HHApAKUAAAAA.Boomertunes:BAAALgAECgYJEwAAAA==.',
Br='Brein:BAABLgAECn8bAAITAAgJvST2AQBCAwATAAgJvST2AQBCAwAAAA==.Brewmaster:BAAALgADCgEJAQAAAA==.Brewwmaster:BAABLgAECn8aAAQUAAgJgBfACwBUAQAMAAYJtBfQfACKAQAUAAgJaxPACwBUAQAVAAEJ+he2FgA2AAAAAA==.Brickred:BAAALgADCggJDgAAAA==.Brynodd:BAAALgADCgkJFgAAAA==.',
Bu='Bubblybetty:BAAALgAECgEJAQAAAA==.Bucketeer:BAABLgAECn8ZAAIDAAYJ7R0wMACjAQADAAYJ7R0wMACjAQAAAA==.Buffs:BAAALgADCgEJAQAAAA==.Bursona:BAAALgAECgEJAQAAAA==.Butterfree:BAAALgAECgUJDAAAAA==.',
Ca='Cards:BAAALgAECgYJCQAAAA==.Carkrash:BAAALgADCgkJFwAAAA==.Casterkang:BAAALgAECgUJCQAAAA==.Catshunter:BAAALgAECgUJCQAAAA==.',
Ce='Celaa:BAABLgAECn8WAAIDAAgJjApCOQCDAQADAAgJjApCOQCDAQAAAA==.',
Ch='Chanka:BAAALgAECgQJBAAAAA==.Chantillary:BAAALgADCgkJFgAAAA==.Chargerkang:BAAALgADCgYJBgAAAA==.Chchanges:BAAALgAECgEJAQAAAA==.Cheesy:BAAALgAECgcJEgAAAA==.Chicken:BAAALgAECgYJDQAAAA==.Chonk:BAAALgADCgEJAQAAAA==.Chopzullee:BAAALgAECgUJCQAAAA==.',
Ci='Cirya:BAAALgAECgUJBQAAAA==.',
Cl='Cleric:BAAALgADCgUJBQAAAA==.Clortho:BAAALgADCggJFQAAAA==.',
Co='Colljack:BAACLgAFFH8QAAIHAAUJih3eBAClAQAHAAUJih3eBAClAQAuAAQKfxoAAwcACQl3IpwJANcCAAcACAktIpwJANcCAAQABQlOEsu5ABIBAAAA.',
Cr='Crocbait:BAAALgAECgYJDwAAAA==.Cryptoe:BAAALgAECgYJEwAAAA==.',
Cu='Cudlsac:BAAALgAECgQJBQAAAA==.',
Da='Daedelus:BAAALgAECgcJDAAAAA==.Daglon:BAAALgAECgcJCQAAAA==.Dagz:BAAALgAECgQJBAAAAA==.Dakina:BAAALgADCgYJBgAAAA==.Daraedra:BAAALgADCgYJDAAAAA==.Darkenvoid:BAAALgADCgkJDQAAAA==.',
De='Deathslight:BAAALgAECgQJBwAAAA==.Deeznutticus:BAACLgAFFH8TAAINAAUJ6RYPBgBjAQANAAUJ6RYPBgBjAQAuAAQKfx8AAw0ABwnCIkkYAIkCAA0ABwnCIkkYAIkCABIAAQkSFhg8AEEAAAAA.Defnotisis:BAABLgAECn8UAAMWAAgJJBClHwDpAAAWAAgJmQulHwDpAAAXAAYJ+g+PNACNAAABLgAFFAEJAQAGAAAAAA==.Demonspud:BAABLgAECn8UAAIQAAYJ9BBqOgD7AAAQAAYJ9BBqOgD7AAAAAA==.Dersan:BAAALgAECgYJDAAAAA==.Destriant:BAABLgAECn8lAAIYAAgJFBgmCQBCAgAYAAgJFBgmCQBCAgAAAA==.Devilschant:BAAALgAECgYJCgAAAA==.Devilshadow:BAAALgAECgUJBwABLgAECgYJCgAGAAAAAA==.Dewburt:BAAALgADCgUJBQAAAA==.Deylia:BAAALgADCgYJBgABLgAFFAMJBgAZACwOAA==.',
Di='Dilithia:BAAALgAECgEJAQAAAA==.Dillion:BAAALgAECgYJCAAAAA==.Dinonuggies:BAAALgADCgcJBwAAAA==.Dionin:BAAALgADCgYJCQAAAA==.Dira:BAAALgAECgYJEAAAAA==.Dirkbanne:BAAALgADCgYJBgAAAA==.',
Do='Dodoubleg:BAAALgAECgYJEAAAAA==.Dominique:BAAALgADCgYJBgAAAA==.Donzilch:BAEALgAECgQJBAAAAA==.',
Dr='Dracaric:BAABLgAECn8XAAIaAAcJeheFDQCyAQAaAAcJeheFDQCyAQAAAA==.Dragondznut:BAAALgAECgQJBQAAAA==.Drfrostie:BAAALgAECgcJBwAAAA==.Drgunner:BAAALgAECgcJDwAAAA==.Driatin:BAAALgAECgIJBAABLgAECgUJDAAGAAAAAA==.Drkladykikyo:BAAALgAECgYJDgAAAA==.Druroo:BAAALgAECgEJAQABLgAECggJGwAZAF8dAA==.Druterr:BAAALgAECgIJAgAAAA==.',
Du='Dumb:BAACLgAFFH8PAAIbAAUJLAyMBgCJAQAbAAUJLAyMBgCJAQAuAAQKfyMAAhsACAnoG2sLAH4CABsACAnoG2sLAH4CAAAA.Durø:BAABLgAECn8WAAIQAAgJriLfDAAZAwAQAAgJriLfDAAZAwAAAA==.',
Dy='Dyanisian:BAAALgADCgYJCAAAAA==.',
['Dè']='Dègenerate:BAABLgAECn8lAAIcAAgJ9SDeAQCjAgAcAAgJ9SDeAQCjAgAAAA==.',
Ed='Edagerran:BAAALgADCgkJCQAAAA==.',
Ei='Eilae:BAAALgAECgQJBQAAAA==.Eirhakan:BAAALgAECgQJBgAAAA==.',
El='Elrethyl:BAAALgAECgYJDwAAAA==.Elvanus:BAAALgADCgYJBgAAAA==.Elêktra:BAABLgAECn8dAAIdAAYJ6hBQIAAYAQAdAAYJ6hBQIAAYAQAAAA==.',
Ep='Epicnym:BAAALgADCgcJBwAAAA==.Epicsmoke:BAABLgAECn8kAAINAAgJfxzlDADiAQANAAgJfxzlDADiAQAAAA==.Epidemius:BAAALgAECggJCAAAAA==.',
Er='Erevan:BAABLgAECn8WAAMRAAgJVQiFDgCDAQARAAgJVQiFDgCDAQAeAAEJpwAAEAAcAAAAAA==.Eroica:BAAALgADCgYJBwAAAA==.',
Es='Esdeath:BAABLgAECn8eAAIMAAcJ0BP9NwBaAQAMAAcJ0BP9NwBaAQAAAA==.',
Et='Etharia:BAAALgADCgUJAwAAAA==.',
Ev='Evilsmeghead:BAAALgADCgEJAQAAAA==.',
Ex='Extenze:BAABLgAECn8ZAAIQAAcJoxw4DwD6AQAQAAcJoxw4DwD6AQAAAA==.',
Ez='Ezykiah:BAAALgADCgcJDAAAAA==.',
Fa='Falconponch:BAAALgADCgEJAQAAAA==.',
Fe='Felgibson:BAAALgAECgQJBQAAAA==.Felkang:BAAALgADCgkJCQAAAA==.Ferryman:BAAALgAECgQJBQAAAA==.',
Fl='Flingor:BAAALgAECgYJEAAAAA==.Flokha:BAAALgADCgEJAQAAAA==.',
Fo='Forphium:BAACLgAFFH8RAAIRAAUJJw2iBACkAQARAAUJJw2iBACkAQAuAAQKfxsAAhEACQlTH3wNAMQCABEACQlTH3wNAMQCAAAA.',
Fr='Fredolf:BAAALgADCgkJCgAAAA==.Freydís:BAAALgAECgUJCwAAAA==.Friarkuck:BAAALgADCggJCAAAAA==.Friedbones:BAAALgADCgkJFAAAAA==.',
Ga='Gahlina:BAAALgAECgIJAwAAAA==.Galdorian:BAAALgADCgMJAwABLgAECgcJFQALALIJAA==.Galynda:BAAALgADCgQJBQAAAA==.',
Ge='Genjimain:BAABLgAECn8cAAITAAgJDRqSHgBKAgATAAgJDRqSHgBKAgAAAA==.Genjí:BAAALgAECgEJAgAAAA==.Geris:BAAALgAECgQJBQAAAA==.Gertruide:BAAALgADCgUJBQAAAA==.',
Gh='Ghendala:BAAALgADCggJDgAAAA==.',
Gi='Gillesmon:BAAALgAECgYJCAABLgAECgcJCQAGAAAAAA==.Gincainn:BAAALgAECgEJAgAAAA==.Gird:BAABLgAECn8eAAIHAAcJswvLHABkAQAHAAcJswvLHABkAQAAAA==.',
Gl='Glaiveyjones:BAAALgAECgEJAQAAAA==.',
Go='Goatmonger:BAAALgAECgYJBgAAAA==.Goinpostal:BAAALgAECgIJAgAAAA==.Goldblade:BAAALgAECgkJBAAAAA==.Gordek:BAABLgAECn8UAAMEAAcJNhrAJgCoAQAEAAcJNhrAJgCoAQAHAAIJfxDgPAB3AAAAAA==.Gothitelle:BAAALgAECgEJAQAAAA==.Goöse:BAACLgAFFH8SAAIMAAUJ4yHXAwDEAQAMAAUJ4yHXAwDEAQAuAAQKfyAAAgwACAmDJusGAGsDAAwACAmDJusGAGsDAAAA.',
Gr='Grantaron:BAABLgAECn8lAAIEAAgJ1x6/DwBAAgAEAAgJ1x6/DwBAAgAAAA==.Gravarii:BAAALgADCgcJEwAAAA==.Grimskul:BAABLgAECn8aAAMMAAgJTRU5IgC6AQAMAAgJBRM5IgC6AQAVAAYJDxSUBwCBAQAAAA==.Grntitan:BAAALgAECgEJAQAAAA==.Gruid:BAAALgADCgcJCgAAAA==.',
Gu='Guinessbrew:BAAALgAECgEJAQAAAA==.',
Gw='Gwoohoori:BAAALgAECgQJAwAAAA==.',
Gy='Gyra:BAAALgAECgYJDwAAAA==.',
Ha='Halukari:BAAALgAECgYJCgABLgAFFAMJBgAZACwOAA==.Harfnan:BAAALgAECgIJAgAAAA==.Harrin:BAABLgAECn8UAAIDAAcJlg4nuABwAQADAAcJlg4nuABwAQAAAA==.',
He='Healingwater:BAAALgADCgEJAQAAAA==.Hezrel:BAAALgAECgUJCAAAAA==.',
Hi='Hierodule:BAAALgAECgEJAQAAAA==.Hiimriven:BAAALgAECgIJAgABLgAECgYJFgARAFkhAA==.Hinal:BAAALgAECgcJDgAAAA==.',
Ho='Hojo:BAAALgADCgUJCAAAAA==.Holyenabler:BAAALgAECgYJCwAAAA==.Hootiehoo:BAAALgADCgMJAwAAAA==.',
Hu='Huflunggoo:BAAALgADCgkJDQAAAA==.Huflungpoop:BAABLgAECn8jAAIWAAcJyRcaDgCYAQAWAAcJyRcaDgCYAQAAAA==.Hunterborn:BAAALgAFFAIJAgAAAA==.',
['Hè']='Hèalz:BAAALgADCgcJCQABLgAECggJFAANAO0UAA==.',
Ic='Ickixia:BAAALgADCgQJBAAAAA==.',
Il='Ilkaressa:BAAALgADCgQJBAAAAA==.Illyríá:BAEALgAFFAIJAgABLgAECggJGgABAIQYAA==.Ilun:BAAALgAECgEJAQAAAA==.',
Im='Imcruel:BAACLgAFFH8MAAIDAAUJcxyhFwBrAQADAAUJcxyhFwBrAQAuAAQKfx4AAgMACAmsI+wYABYCAAMACAmsI+wYABYCAAAA.',
In='Ink:BAABLgAECn8gAAIDAAcJsSBQGAAbAgADAAcJsSBQGAAbAgAAAA==.',
Is='Istaria:BAAALgADCgkJFAAAAA==.Isujr:BAABLgAECn8ZAAIMAAcJ8hICcQCmAQAMAAcJ8hICcQCmAQAAAA==.',
Ja='Jackiegan:BAAALgAECgcJEQAAAA==.Jackson:BAAALgADCgkJFgAAAA==.Jagerdemon:BAAALgAECgcJBwAAAA==.',
Je='Jerce:BAAALgADCgUJBQAAAA==.',
Jh='Jhala:BAAALgADCgcJCAAAAA==.',
Jo='Joshcalc:BAAALgAECgEJAQAAAA==.Joskel:BAABLgAECn8bAAMCAAYJSA8nQAAxAQACAAYJSA8nQAAxAQAfAAUJEgPnFgDIAAAAAA==.',
Ju='Juacqer:BAAALgADCggJFAAAAA==.',
Ka='Kaant:BAABLgAECn8bAAMdAAgJphkTDwCxAQAdAAcJnBgTDwCxAQAIAAUJyhNEVgAuAQAAAA==.Kaeni:BAAALgADCgMJAwAAAA==.Kaidevyn:BAABLgAECn8YAAMVAAcJWxD3BwByAQAVAAcJWxD3BwByAQAMAAMJIg7siQCAAAAAAA==.Kaiste:BAAALgADCgEJAQAAAA==.Kaleine:BAAALgAECgIJAgAAAA==.Kardren:BAAALgAECgMJAwAAAA==.',
Ke='Keiko:BAAALgAECgcJCgAAAA==.Keiran:BAABLgAECn8lAAMLAAgJ8SBOBQClAgALAAgJ1SBOBQClAgAJAAgJphyUEgCfAgAAAA==.Kelazurin:BAAALgADCgEJAQAAAA==.Kellistair:BAAALgADCgYJBgAAAA==.Keläo:BAAALgADCgUJCQAAAA==.Keyadish:BAAALgADCgYJBwAAAA==.Keys:BAABLgAECn8jAAIRAAgJvxu2EACcAgARAAgJvxu2EACcAgAAAA==.',
Kh='Khalnerys:BAABLgAECn8UAAMOAAYJkAWMDACQAAAaAAYJrAQgMwCRAAAOAAQJWwWMDACQAAAAAA==.Khoulock:BAACLgAFFH8JAAICAAQJHxeYHAAvAQACAAQJHxeYHAAvAQAuAAQKfykAAwIACQlNIGQHAJcCAAIACQlNIGQHAJcCAAEAAwl9ENQ+ALkAAAAA.',
Ki='Kimmispally:BAAALgAECgIJAwAAAA==.Kiro:BAAALgADCgQJBQAAAA==.',
Ko='Kotateal:BAAALgAECgYJCwAAAA==.',
Kr='Kruelshot:BAAALgAECgcJCQABLgAFFAUJDAADAHMcAA==.Krux:BAAALgAECgEJAQAAAA==.',
Kt='Kthxbye:BAAALgADCgMJAwABLgAECgcJBwAGAAAAAA==.',
Ku='Kumcookies:BAAALgADCgEJAQAAAA==.Kungfuprissy:BAAALgAECgEJAQAAAA==.Kuraishin:BAACLgAFFH8IAAIgAAIJiQ1VBQCqAAAgAAIJiQ1VBQCqAAAuAAQKf0gAAyAABwmsH+QCAC0CACAABwmsH+QCAC0CACEAAwmdHBYaAN0AAAEuAAUUAgkKAAwAsBAA.Kuroakuma:BAAALgAECgYJEAAAAA==.Kuvara:BAAALgADCgkJCgAAAA==.',
Kv='Kvnpro:BAAALgADCgEJAQAAAA==.',
Kw='Kwandashadow:BAAALgAECgUJCAAAAA==.',
Ky='Kylemonk:BAAALgADCgEJAQAAAA==.',
['Ké']='Kéres:BAAALgADCgkJEAAAAA==.',
La='Lagspike:BAABLgAECn8dAAIDAAgJphVMlgCnAQADAAgJphVMlgCnAQAAAA==.Latheal:BAAALgADCggJDgAAAA==.Lavi:BAABLgAECn8UAAIEAAYJsQuOVgAMAQAEAAYJsQuOVgAMAQAAAA==.',
Lb='Lbk:BAAALgADCgIJAgAAAA==.',
Le='Lejeune:BAAALgADCgcJFQAAAA==.Lengex:BAAALgAECgYJCAAAAA==.Lero:BAABLgAECn8hAAIXAAgJZiPQAQDXAgAXAAgJZiPQAQDXAgAAAA==.Lerwindion:BAABLgAECn8bAAIZAAgJXx2SCQCiAgAZAAgJXx2SCQCiAgAAAA==.Lescaryn:BAAALgADCgIJAgAAAA==.Lexoh:BAAALgAECgYJEgAAAA==.',
Li='Lilani:BAAALgADCgQJBAAAAA==.Lindir:BAACLgAFFH8FAAIKAAMJkRDPCQAEAQAKAAMJkRDPCQAEAQAuAAQKfycAAgoACAk5JFYBAMsCAAoACAk5JFYBAMsCAAAA.Lionelle:BAAALgAECgYJDgAAAA==.Liquor:BAACLgAFFH8FAAIQAAMJJROOHQD0AAAQAAMJJROOHQD0AAAuAAQKfycAAxAACQnoHqUCANwCABAACQnoHqUCANwCAAUAAwnLFOQhAHQAAAAA.Lirathiel:BAAALgAECgIJAwAAAA==.Litasfk:BAAALgAECgIJAgAAAA==.Liuni:BAABLgAECn8eAAIXAAcJzxV0FABhAQAXAAcJzxV0FABhAQAAAA==.Liyin:BAAALgAECgIJAwABLgAECggJFgADAIwKAA==.',
Lo='Lobopeste:BAABLgAECn8bAAIUAAgJTAZXGwCgAAAUAAgJTAZXGwCgAAAAAA==.Locknutz:BAAALgADCgMJAwAAAA==.Loracy:BAAALgADCgcJBwAAAA==.Lorelynn:BAABLgAECn8XAAICAAcJfQxhOgBEAQACAAcJfQxhOgBEAQAAAA==.',
Lu='Luci:BAAALgAECgYJCQABLgAFFAEJAQAGAAAAAA==.Lucìan:BAABLgAECn8VAAITAAYJCCDhFADeAQATAAYJCCDhFADeAQAAAA==.Ludociel:BAAALgADCgkJEQAAAA==.Lunaclair:BAACLgAFFH8KAAIMAAIJsBAjVQChAAAMAAIJsBAjVQChAAAuAAQKfzIAAwwACAmDF/k2AF4BAAwACAmDF/k2AF4BABQAAglRBvpCAD4AAAAA.Lunadrus:BAABLgAECn8VAAIDAAcJnwjZYQAYAQADAAcJnwjZYQAYAQAAAA==.Lunarielle:BAABLgAECn8aAAILAAcJKx3GFQCJAgALAAcJKx3GFQCJAgAAAA==.',
Ly='Lyriaa:BAAALgADCgYJCwAAAA==.',
Ma='Macfly:BAABLgAECn8gAAILAAcJihYPIgCWAQALAAcJihYPIgCWAQAAAA==.Madmeatballs:BAAALgADCgIJAgABLgAECgYJGQADAO0dAA==.Magicmissile:BAABLgAECn8hAAIDAAgJ0xzqEQBMAgADAAgJ0xzqEQBMAgAAAA==.Makgora:BAAALgAECgMJBAABLgAECgYJFgARAFkhAA==.Makhvan:BAAALgAECgMJAwAAAA==.Maksoon:BAAALgAECgUJDAAAAA==.Maladjusted:BAAALgAECgMJBAAAAA==.Maléfique:BAAALgADCgkJEAAAAA==.Mancath:BAAALgAECggJCAAAAA==.Maplè:BAAALgAECgIJAgABLgAECggJHgAIAKATAA==.Mar:BAAALgADCgMJAwAAAA==.Marlei:BAAALgADCgQJBAABLgAECggJFgADAIwKAA==.Marqose:BAAALgADCgYJBgAAAA==.Matan:BAAALgADCgUJBQAAAA==.',
Me='Melfie:BAAALgAECgcJDQAAAA==.Meliadoul:BAAALgAECgUJCwAAAA==.Mellyndra:BAABLgAECn8bAAIHAAgJSxtpDwDrAQAHAAgJSxtpDwDrAQAAAA==.Mercüry:BAAALgAECgEJAgAAAA==.Mezhren:BAAALgAECgYJBwAAAA==.',
Mh='Mhoramsgirl:BAAALgADCggJCgAAAA==.',
Mi='Midoriya:BAABLgAECn8eAAMWAAgJ+hAmKACZAQAWAAcJ0hEmKACZAQAiAAQJVA6dVAB+AAAAAA==.Mistjack:BAAALgAFFAQJBAAAAA==.',
Mo='Momdad:BAACLgAFFH8FAAIKAAMJvBtaBwAkAQAKAAMJvBtaBwAkAQAuAAQKfyYAAgoACQmJHwYBAOQCAAoACQmJHwYBAOQCAAAA.Mongaux:BAAALgADCgQJBQAAAA==.Monkey:BAAALgAECgEJBAAAAA==.Morrígán:BAAALgADCgUJBQAAAA==.Moxi:BAAALgADCggJDQAAAA==.',
Mu='Muamman:BAAALgAECgMJAwAAAA==.Murda:BAAALgADCgYJCgAAAA==.Murphysflaw:BAAALgADCgUJCAAAAA==.Mutegen:BAAALgAECgUJBwAAAA==.',
Mx='Mxhealeryduf:BAAALgAECgIJAgAAAA==.',
My='Mystallian:BAAALgAECgEJAQAAAA==.Mythicplus:BAAALgAECgcJCwAAAA==.',
['Mé']='Mémnoc:BAAALgAECgMJAwAAAA==.',
Na='Nadarien:BAAALgAECgYJDQAAAA==.Nadyia:BAAALgADCgEJAQAAAA==.Nailah:BAAALgADCgcJCwAAAA==.Nannergoat:BAAALgADCgMJAwAAAA==.Nastymikey:BAABLgAECn8VAAIjAAgJfhp2BwBzAgAjAAgJfhp2BwBzAgAAAA==.Nazdormu:BAAALgAECgYJEAAAAA==.',
Ne='Nefarious:BAAALgAECgYJBgAAAA==.Neisen:BAABLgAECn8YAAMHAAgJig/eOgCOAQAHAAcJuw3eOgCOAQAEAAUJBwKP+gCeAAAAAA==.Neptune:BAAALgADCgYJBgAAAA==.',
No='Norna:BAAALgADCgUJCgAAAA==.',
Nu='Nufonewhodis:BAABLgAECn8WAAIRAAYJWSFyHQATAgARAAYJWSFyHQATAgAAAA==.',
Ny='Nykolas:BAAALgADCgkJDAAAAA==.Nymofthedead:BAAALgAECgYJDAAAAA==.',
Oa='Oakgrove:BAAALgADCgQJBAAAAA==.',
Om='Ombraless:BAAALgADCgMJAwABLgAECgQJBgAGAAAAAA==.',
Op='Ophrizhani:BAAALgAECgMJAwAAAA==.',
Or='Orangegrove:BAAALgAECgEJAQAAAA==.Orpheal:BAAALgAECgUJBQAAAA==.Orphen:BAAALgADCgYJBgAAAA==.',
Pa='Paddleball:BAAALgADCgQJBAAAAA==.Paladouin:BAAALgAECgYJEwAAAA==.Pandammy:BAAALgAECgkJAgAAAA==.Pantro:BAAALgAECgQJBgAAAA==.Papalion:BAAALgAECgQJBQAAAA==.Paragas:BAAALgADCgkJEAAAAA==.Pawbs:BAAALgAECgQJCQAAAA==.',
Pe='Peanuts:BAAALgADCgcJBwAAAA==.Peoplehugger:BAAALgADCgMJAwAAAA==.',
Pi='Pickleburger:BAAALgAECgEJAQAAAA==.Pinklilydrd:BAAALgADCgkJFgAAAA==.',
Pl='Plaindonut:BAAALgAECgYJBgAAAA==.',
Pr='Priestdrago:BAAALgADCgUJBQAAAA==.Prissidebow:BAAALgADCgkJFwAAAA==.',
Ra='Ralynne:BAABLgAECn8iAAIdAAgJKw5YGABPAQAdAAgJKw5YGABPAQAAAA==.Ravenbrook:BAACLgAFFH8IAAINAAMJRyUoCgBEAQANAAMJRyUoCgBEAQAuAAQKfxsAAw0ACAmwJIEEAGIDAA0ACAmwJIEEAGIDABIAAQkwIBokAF4AAAAA.Rawrr:BAAALgAECgYJEAAAAA==.Raxie:BAACLgAFFH8GAAMZAAMJLA4wEgDpAAAZAAMJLA4wEgDpAAAkAAEJBQ3IFABRAAAuAAQKfygABBkACAlqG+cEAHQCABkACAlqG+cEAHQCACQABwmzEKMRAHsBAA8AAQkBBOmHACgAAAAA.Razeth:BAAALgAECgYJDwAAAA==.',
Re='Reanne:BAAALgAECgYJEAAAAA==.Res:BAAALgAECgYJCwAAAA==.Rescorla:BAAALgAECgYJBgAAAA==.Rethali:BAAALgADCgQJAgAAAA==.Rezr:BAAALgAECgcJDAAAAA==.',
Rh='Rhixa:BAAALgADCgUJBQAAAA==.',
Ri='Rifthor:BAAALgAECgUJCQAAAA==.Rillx:BAAALgADCgQJBgAAAA==.Ripmxi:BAABLgAECn8dAAIDAAcJnBBmVgAyAQADAAcJnBBmVgAyAQAAAA==.',
Ro='Robinski:BAAALgADCgEJAQAAAA==.Robotiss:BAAALgADCgIJAgAAAA==.Rodevon:BAAALgADCggJCAAAAA==.Roknasaurus:BAAALgADCgUJCAAAAA==.Romani:BAAALgADCgYJBgAAAA==.Romeo:BAAALgADCgMJAwAAAA==.Ronaldreagnt:BAAALgAECgcJCQAAAA==.',
Ru='Runelight:BAAALgAECgUJBwAAAA==.Rupertgiless:BAACLgAFFH8HAAICAAQJVwn8HgAmAQACAAQJVwn8HgAmAQAuAAQKfyAAAgIACQkzGnoiAIsCAAIACQkzGnoiAIsCAAAA.',
Sa='Sabeckya:BAAALgAECgMJBgAAAA==.Sacksmasher:BAAALgADCgcJDwAAAA==.Sampleshrimp:BAAALgADCgEJAgAAAA==.Saphyla:BAAALgADCgcJCwAAAA==.Sarcastyx:BAAALgAECgUJBgAAAA==.Saxines:BAAALgAECgQJBgAAAA==.',
Sc='Scaliefox:BAAALgAECgIJAgABLgAECggJGwAHAEsbAA==.Scarl:BAAALgADCgUJBQAAAA==.Schwarznacht:BAAALgADCgUJBQAAAA==.Schwarzwölf:BAAALgADCgYJCwAAAA==.Scoots:BAAALgADCgQJBAAAAA==.Scrubs:BAAALgAECgUJCAAAAA==.Scrubsevoker:BAAALgADCgYJCAAAAA==.Scumbum:BAAALgADCgIJAgAAAA==.Scyllo:BAAALgAECgQJBAAAAA==.',
Se='Seekndestroy:BAAALgAECgQJBQAAAA==.Selige:BAAALgAECgQJBAAAAA==.',
Sg='Sgtcuunt:BAAALgADCgQJBAAAAA==.',
Sh='Shaenicor:BAAALgADCgIJAgAAAA==.Shelbo:BAAALgADCgcJCQAAAA==.Shortshammy:BAAALgAECgEJAQABLgAFFAMJCAADAKcFAA==.Shror:BAAALgADCgEJAQABLgAECgUJBQAGAAAAAA==.',
Si='Sicarune:BAAALgAECgEJAQAAAA==.Siiegrand:BAAALgAECgYJDgAAAA==.Silentswag:BAAALgADCgUJBQAAAA==.Sindrane:BAAALgADCgEJAQABLgAECggJJQAMABgWAA==.Sitzho:BAAALgADCgUJCAAAAA==.',
Sk='Skeleton:BAAALgAECgIJAgAAAA==.Skybringer:BAABLgAECn8dAAIEAAYJVgqyWAAGAQAEAAYJVgqyWAAGAQAAAA==.Skyee:BAABLgAECn8lAAMWAAgJhh0HDAC6AgAWAAgJhh0HDAC6AgAiAAMJGBQ2KwCtAAAAAA==.Skylos:BAAALgAECgEJAgAAAA==.',
So='Soapscum:BAAALgADCgQJBAAAAA==.Soarphium:BAAALgAECgIJAgABLgAFFAUJEQARACcNAA==.Solararc:BAAALgADCgEJAQAAAA==.Soleana:BAAALgAECgYJBQAAAA==.Sonicast:BAAALgAECgYJBgAAAA==.Sooie:BAAALgAECgYJEQAAAA==.Soramian:BAAALgADCgcJEgAAAA==.Soulcacher:BAABLgAECn8lAAIMAAgJGBaKIQC+AQAMAAgJGBaKIQC+AQAAAA==.Soxxy:BAAALgAECgEJAQABLgAFFAEJAQAGAAAAAA==.',
Sp='Spellgunner:BAABLgAECn8VAAIDAAgJRhs0GwAIAgADAAgJRhs0GwAIAgAAAA==.',
St='Stormwulf:BAAALgADCgUJBQABLgADCgkJEwAGAAAAAA==.Strombjorn:BAABLgAECn8eAAIIAAgJoBO9EwDPAQAIAAgJoBO9EwDPAQAAAA==.',
['Sø']='Sølaria:BAAALgAECgEJAQAAAA==.',
Ta='Tasireth:BAAALgADCgcJBwAAAA==.',
Te='Tessi:BAAALgAECgYJCwAAAA==.',
Th='Thalrian:BAAALgAECgQJBQABLgAECggJKQANANYiAA==.Thefailnym:BAAALgAECggJCAAAAA==.Theylive:BAAALgAECgQJCgAAAA==.Thondrin:BAAALgAECgMJBAAAAA==.Thrashedass:BAAALgADCgEJAQAAAA==.',
Ti='Tigerlilliy:BAAALgADCgYJEAAAAA==.Tim:BAAALgADCgUJBQAAAA==.Timerek:BAAALgADCgIJAgAAAA==.',
To='Toawulf:BAAALgADCgYJCQABLgADCgkJEwAGAAAAAA==.Toya:BAABLgAECn8bAAIRAAcJShsYGgAxAgARAAcJShsYGgAxAgAAAA==.',
Tr='Trenazen:BAAALgADCgEJAQAAAA==.Trevain:BAAALgADCgkJFgAAAA==.Trimasdrood:BAAALgADCgMJAwAAAA==.Trivia:BAAALgADCgYJEQAAAA==.Truthordare:BAABLgAECn8VAAIBAAYJdwfMDwC1AAABAAYJdwfMDwC1AAAAAA==.',
Tu='Turtei:BAAALgAECgEJAQABLgAFFAUJEwAWAJslAA==.Turtl:BAACLgAFFH8TAAIWAAUJmyWtAADCAQAWAAUJmyWtAADCAQAuAAQKfyMAAhYACQlnJjcAAPgDABYACQlnJjcAAPgDAAAA.',
Tw='Twohoof:BAAALgADCgEJAQAAAA==.',
Tx='Txìewtkuä:BAAALgADCgkJCQAAAA==.',
Ty='Tyryn:BAAALgADCgMJBAAAAA==.',
Ug='Uglydragon:BAAALgAECgcJDAAAAA==.Uglypally:BAAALgADCgkJCQAAAA==.Uglypetguy:BAAALgAECgIJAgAAAA==.Uglyrogue:BAAALgAECgQJAgAAAA==.Uglyshaman:BAAALgAECgEJAgAAAA==.',
Ul='Ulgrym:BAAALgADCggJDwAAAA==.Ultimatia:BAAALgADCgMJBwAAAA==.',
Un='Unbalancéd:BAAALgAECgEJAQAAAA==.',
Va='Vahra:BAAALgADCgkJFAAAAA==.Valanther:BAAALgAECgMJAwAAAA==.Valantis:BAAALgADCgEJAQAAAA==.Valgaskav:BAABLgAECn8UAAIEAAYJHiHvPwAmAgAEAAYJHiHvPwAmAgAAAA==.Valimond:BAAALgAECgEJAQABLgADCgkJEwAGAAAAAA==.Valric:BAAALgADCgUJBQAAAA==.Vanarrath:BAAALgADCgYJBwAAAA==.Vandryelle:BAAALgADCgIJAgAAAA==.Varge:BAAALgADCgMJAwAAAA==.Varrathos:BAAALgADCgkJEgAAAA==.Vayl:BAAALgAECgMJAwAAAA==.',
Ve='Velisa:BAAALgADCgYJBgAAAA==.Verdesoul:BAAALgAECgQJBAAAAA==.Vesyra:BAAALgAECgQJBQAAAA==.',
Vi='Viralyn:BAAALgADCgMJAwABLgAECgcJHgAXAM8VAA==.',
Vo='Voidluck:BAABLgAECn8SAAIQAAgJZRBfdABIAQAQAAgJZRBfdABIAQAAAA==.Voker:BAAALgAECgIJBQABLgAECgQJCQAGAAAAAA==.Voladis:BAAALgAECgIJAgAAAA==.Voladro:BAAALgAECgQJBAAAAA==.Volos:BAAALgAECgYJEwAAAA==.Vordaman:BAABLgAECn8kAAIMAAgJFRU+JgCmAQAMAAgJFRU+JgCmAQAAAA==.',
Vy='Vynír:BAACLgAFFH8QAAICAAQJZBu1DgBoAQACAAQJZBu1DgBoAQAuAAQKfyMAAwEACAnnIowNAOwBAAEABQkHI4wNAOwBAAIABwn0Im0qAIQBAAAA.',
Wa='Waghoba:BAECLgAFFH8RAAIgAAUJ2hVTAQBxAQAgAAUJ2hVTAQBxAQAuAAQKfx8AAiAABwkMIicGAJwCACAABwkMIicGAJwCAAAA.Waito:BAAALgAECgQJBAAAAA==.Wandä:BAABLgAECn8ZAAQXAAgJjRe/CgDeAQAXAAgJHhW/CgDeAQAWAAgJwhBkDACxAQAiAAEJrg5PRgAuAAAAAA==.Wardriccan:BAAALgAECgUJCwAAAA==.Warfle:BAAALgADCgYJBgAAAA==.Warrionomous:BAAALgAECgYJCwABLgAECggJIQADANMcAA==.Washu:BAABLgAECn8cAAMlAAgJAxstCQCzAQAlAAgJAxstCQCzAQAFAAMJTAtZIQB5AAAAAA==.',
Wh='Whimlock:BAAALgADCgQJBAABLgAFFAEJAwAGAAAAAA==.Whims:BAAALgAECgYJBwABLgAFFAEJAwAGAAAAAA==.Whimzie:BAAALgAECgEJAQABLgAFFAEJAwAGAAAAAA==.Whorphium:BAAALgAECggJDAABLgAFFAUJEQARACcNAA==.',
Wi='Willow:BAAALgAECgYJCwAAAA==.Wims:BAAALgAECgMJAwABLgAFFAEJAwAGAAAAAA==.Winterous:BAAALgAECgEJAQAAAA==.',
Wo='Wonderbread:BAABLgAECn8hAAIEAAgJLxIuOQBgAQAEAAgJLxIuOQBgAQAAAA==.',
Wr='Wrager:BAAALgAECgUJBgAAAA==.Wrathofzaun:BAAALgAECgYJDwAAAA==.',
Wy='Wylest:BAAALgADCgcJBwAAAA==.Wynch:BAAALgAECgkJCAAAAA==.',
['Wâ']='Wârwôlf:BAABLgAECn8UAAMLAAcJFBplNABAAQALAAYJLhplNABAAQAJAAQJ7RWPVQDzAAAAAA==.',
Xe='Xenan:BAABLgAECn8YAAIEAAgJOAtYNgBqAQAEAAgJOAtYNgBqAQAAAA==.',
Xt='Xtrolldinary:BAAALgAECgMJBgAAAA==.',
Xv='Xvp:BAAALgAECgQJBgAAAA==.',
Xy='Xylophy:BAABLgAECn8cAAIFAAcJbREzBwBLAQAFAAcJbREzBwBLAQAAAA==.',
Ye='Yeastmode:BAACLgAFFH8HAAILAAMJHgrXHADvAAALAAMJHgrXHADvAAAuAAQKfx4AAgsACAloGs4aAGYCAAsACAloGs4aAGYCAAAA.',
Yo='Yonah:BAAALgAECgYJDAAAAA==.',
Yu='Yurc:BAABLgAECn8UAAIcAAYJMhikHwBFAQAcAAYJMhikHwBFAQAAAA==.',
Za='Zademan:BAAALgAECgUJBwAAAA==.Zappyu:BAAALgAECgkJBQABLgAECgkJCAAGAAAAAA==.',
Ze='Zeebra:BAAALgAECgEJAQAAAA==.Zeg:BAAALgADCgkJCQAAAA==.Zega:BAAALgAECgEJAQAAAA==.Zegafur:BAABLgAECn8hAAITAAcJOx6LEgD2AQATAAcJOx6LEgD2AQAAAA==.Zeruk:BAABLgAECn8XAAMWAAcJjwJpYACOAAAWAAYJlAJpYACOAAAiAAcJmwGMMQCEAAAAAA==.',
Zi='Zillionbúcks:BAACLgAFFH8SAAIEAAUJpRLkBQCRAQAEAAUJpRLkBQCRAQAuAAQKfxoAAgQACQnrHdAtAGwCAAQACQnrHdAtAGwCAAAA.',
Zy='Zylcat:BAAALgAECgQJBgAAAA==.',
['Zê']='Zêddicus:BAABLgAECn8jAAMBAAcJvRuLAgDpAQABAAcJvRuLAgDpAQACAAQJjQj40wCyAAAAAA==.',
['Áq']='Áquafina:BAABLgAECn8iAAIDAAgJDgn0QABrAQADAAgJDgn0QABrAQAAAA==.',
['Îv']='Îvan:BAAALgADCggJCAAAAA==.',
['Ðö']='Ðö:BAABLgAECn8UAAINAAgJ7RTBDADjAQANAAgJ7RTBDADjAQAAAA==.',
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
