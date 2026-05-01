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

local lookup = {'Mage-Arcane','Unknown-Unknown','Paladin-Retribution','Priest-Discipline','Evoker-Augmentation','Rogue-Subtlety','Rogue-Assassination','DeathKnight-Unholy','Hunter-BeastMastery','Shaman-Restoration','DeathKnight-Blood','Mage-Frost','Shaman-Enhancement','Hunter-Marksmanship','Warlock-Demonology','Warlock-Affliction','Priest-Shadow','Warrior-Arms','Warrior-Fury','Monk-Windwalker','DemonHunter-Havoc','Hunter-Survival','Warrior-Protection','Paladin-Holy','DemonHunter-Devourer','Druid-Guardian','Druid-Feral','Warlock-Destruction','Evoker-Preservation','Shaman-Elemental','Druid-Balance','Druid-Restoration','Monk-Mistweaver','Monk-Brewmaster','DemonHunter-Vengeance','Priest-Holy','Rogue-Outlaw','Evoker-Devastation','Paladin-Protection',}
local provider = {region='US',realm='Shadowsong',name='US',type='weekly',zone=46,date='2026-05-01',data={Ad='Adoran:BAAALgADCgEJAQAAAA==.Adorian:BAAALgAECgEJAgAAAA==.Adrenaleen:BAAALgADCgYJCQAAAA==.',
Ae='Aeosi:BAAALgADCgEJAQAAAA==.Aeriss:BAAALgADCgMJAwAAAA==.Aertin:BAAALgADCgQJBAABLgAECggJIAABAOQYAA==.Aeryhn:BAAALgADCgcJDAABLgAECgIJAgACAAAAAA==.Aezili:BAAALgAECgMJBgAAAA==.',
Af='Afkatie:BAAALgAECgMJAwAAAA==.',
Ag='Agaruu:BAAALgAECgYJBgAAAA==.Agerol:BAABLgAECn8UAAIDAAYJNBuuLQCLAQADAAYJNBuuLQCLAQAAAA==.Agnin:BAAALgADCgYJCAAAAA==.',
Ak='Akafabu:BAAALgAECgMJBAABLgAFFAMJCAAEAKoLAA==.Akuryujin:BAABLgAECn8eAAIFAAgJ2Q/HEACHAQAFAAgJ2Q/HEACHAQAAAA==.Akätsuki:BAABLgAECn8VAAIGAAgJ5g6xJADTAQAGAAgJ5g6xJADTAQAAAA==.',
Al='Alacardias:BAABLgAECn8gAAIDAAgJzR1oDABjAgADAAgJzR1oDABjAgAAAA==.Aladistra:BAAALgADCgMJAwAAAA==.Albert:BAAALgADCgIJAgAAAA==.Alcaedra:BAAALgADCggJCAAAAA==.Alcapwnz:BAAALgADCgYJCQAAAA==.Alinoda:BAAALgADCgIJAgAAAA==.Alleril:BAABLgAECn8mAAMHAAkJmg3bBwDeAQAHAAgJRA7bBwDeAQAGAAkJ6AajLwCHAQAAAA==.Alley:BAAALgADCgUJCgAAAA==.',
Am='Amäri:BAACLgAFFH8IAAIEAAMJqgtWEwDZAAAEAAMJqgtWEwDZAAAuAAQKfyYAAgQACAkmFyQSACQCAAQACAkmFyQSACQCAAAA.',
An='Anassand:BAABLgAECn8gAAIIAAgJASRGBQDRAgAIAAgJASRGBQDRAgAAAA==.Andimorph:BAAALgAECgYJBwAAAA==.Anema:BAAALgADCgQJBAABLgAECgMJBQACAAAAAA==.Angeleria:BAABLgAECn8UAAIJAAYJ4BuHJQCEAQAJAAYJ4BuHJQCEAQAAAA==.Antebellum:BAAALgAECgcJBQAAAA==.',
Aq='Aqiqi:BAAALgAECgMJBgAAAA==.Aquashade:BAAALgAECgUJBQABLgAECggJKQAKAPAiAA==.Aquaterra:BAABLgAECn8pAAIKAAgJ8CKIAgD6AgAKAAgJ8CKIAgD6AgAAAA==.',
Ar='Arakadia:BAABLgAECn8hAAMIAAcJDQ9gSAAlAQAIAAcJmwxgSAAlAQALAAQJOww2HgCFAAAAAA==.Aravena:BAAALgADCgMJAwAAAA==.Archetyepe:BAAALgAECgIJBAAAAA==.Arisana:BAAALgAECgMJAwAAAA==.Aruteeru:BAAALgAECgYJDgAAAA==.',
As='Asathen:BAAALgADCgEJAQAAAA==.Aseanna:BAAALgAECgUJBQAAAA==.Ashadala:BAAALgAECgYJBwAAAA==.Astallivan:BAAALgADCgkJFQAAAA==.',
Au='Augabeks:BAACLgAFFH8JAAIFAAQJPw1FEAAuAQAFAAQJPw1FEAAuAQAuAAQKfxoAAgUACAmnFKAZAAACAAUACAmnFKAZAAACAAEuAAMKBwkHAAIAAAAA.Auralada:BAABLgAECn8gAAMBAAgJ5Bh/BAACAgABAAcJcht/BAACAgAMAAgJUREnQABuAQAAAA==.Auxhunt:BAAALgADCgkJDQAAAA==.Auxiliator:BAAALgADCgYJCgABLgADCggJCgACAAAAAA==.',
Ay='Ayala:BAABLgAFFH8RAAIDAAQJQiEgBQCQAQADAAQJQiEgBQCQAQAAAA==.Ayessa:BAAALgAECgUJDQAAAA==.',
Az='Azaireos:BAAALgAECgEJAQAAAA==.Azulpunkt:BAABLgAECn8YAAINAAcJKRZjCABsAQANAAcJKRZjCABsAQAAAA==.Azzapp:BAAALgAECgQJDQAAAA==.',
Ba='Baddaboomkin:BAAALgAECgYJCAAAAA==.Bakreingol:BAAALgADCgUJBQABLgAECgcJBwACAAAAAA==.Barbedwire:BAAALgAECgcJBAAAAA==.Baree:BAAALgAECgMJAwAAAA==.',
Be='Bearmao:BAABLgAECn8oAAMJAAgJiBV4EwD2AQAJAAgJLRV4EwD2AQAOAAcJaQzEQQBQAQAAAA==.Bearserk:BAAALgAECgMJBwAAAA==.Beastknight:BAAALgAECgIJAgAAAA==.Beastrunner:BAAALgADCgkJEQABLgAECgIJAgACAAAAAA==.Beknight:BAAALgAFFAEJAQABLgADCgcJBwACAAAAAA==.Belfas:BAAALgAECgYJCwAAAA==.Bellybutton:BAAALgAECgYJCQAAAA==.Benafflok:BAACLgAFFH8LAAMPAAQJEhdOHQAtAQAPAAQJEhdOHQAtAQAQAAEJRAt2BgBRAAAuAAQKfyYAAw8ACAkzJB8EANwCAA8ACAn/Ix8EANwCABAABwn9H3YDAGMCAAAA.Bertu:BAAALgADCgEJAQAAAA==.',
Bi='Bigblight:BAAALgADCgEJAgAAAA==.Bigduck:BAAALgAECgUJCgAAAA==.Biggayjohn:BAAALgAECgEJAgAAAA==.Bigknighter:BAAALgAECgYJDgAAAA==.',
Bl='Blackclover:BAABLgAECn8fAAIKAAgJjRxKIwALAgAKAAgJjRxKIwALAgAAAA==.Blackpink:BAAALgADCgcJDQAAAA==.Blandicus:BAAALgADCgcJBwAAAA==.',
Bo='Boppaheks:BAAALgADCgcJBwAAAA==.Bowless:BAAALgAECgcJCAAAAA==.',
Br='Brawnstone:BAAALgAECgEJAQAAAA==.Brewsleroy:BAAALgADCgcJDQAAAA==.Brewtypoppin:BAAALgADCgQJBAAAAA==.Brey:BAAALgADCgMJAwAAAA==.Brohomir:BAAALgAECgEJAQAAAA==.Bronze:BAAALgAECgYJCgAAAA==.Brunee:BAABLgAECn8WAAIRAAgJzwpJJwCeAQARAAgJzwpJJwCeAQAAAA==.Bruute:BAABLgAECn8fAAISAAcJ2iD/AgA5AgASAAcJ2iD/AgA5AgAAAA==.',
Bu='Budplatinum:BAAALgAECgQJBwAAAA==.Buffbuffheal:BAAALgAECgMJAwABLgAECgYJCgACAAAAAA==.Buhemoth:BAAALgAECgcJDgAAAA==.Bumi:BAAALgADCgQJBAAAAA==.',
Ca='Caemaris:BAAALgADCgQJBAAAAA==.Cairo:BAABLgAECn8XAAITAAgJrhhJIwA7AgATAAgJrhhJIwA7AgAAAA==.Cakes:BAAALgAECgYJEwAAAA==.Calai:BAAALgADCgYJCgAAAA==.Canadiian:BAAALgAECgYJDwAAAA==.Capitalchaos:BAABLgAECn8eAAITAAgJ+xmrBwAyAgATAAgJ+xmrBwAyAgAAAA==.Cassandraa:BAAALgAECgIJAgAAAA==.',
Ce='Cearrdorn:BAAALgAECgIJAgABLgAECgYJHAADAAgiAA==.Cearreotadh:BAAALgADCgQJBAAAAA==.Ceviche:BAACLgAFFH8JAAIUAAQJsBeKBABRAQAUAAQJsBeKBABRAQAuAAQKfxgAAhQACAkzI7gFACgDABQACAkzI7gFACgDAAAA.Ceàrrdòrn:BAABLgAECn8cAAIDAAYJCCKTJgCpAQADAAYJCCKTJgCpAQAAAA==.',
Ch='Cheetahgirl:BAAALgAECgEJAQAAAA==.Chickenjoy:BAAALgADCgcJBwAAAA==.Chillzmatic:BAACLgAFFH8GAAIVAAQJjQcPBQApAQAVAAQJjQcPBQApAQAuAAQKfxUAAhUABgn2IJgYAAICABUABgn2IJgYAAICAAAA.Chirri:BAAALgAECgMJAwAAAA==.Chondriac:BAAALgAECgcJEQAAAA==.Chow:BAAALgADCgQJBAAAAA==.Chrisdirect:BAAALgADCgQJBAAAAA==.Chudbucket:BAABLgAECn8YAAMWAAUJVxjzEgA6AQAOAAUJvRcXPABtAQAWAAUJCBbzEgA6AQAAAA==.',
Ci='Cilantro:BAAALgADCgEJAQABLgAECgUJCgACAAAAAA==.Cinabun:BAAALgADCgIJAgAAAA==.Cirillø:BAABLgAECn8VAAIXAAkJJh3PAQCoAgAXAAkJJh3PAQCoAgAAAA==.',
Cl='Cloverblack:BAAALgADCgEJAQAAAA==.',
Co='Corbis:BAAALgAECgUJCwAAAA==.Covidmage:BAAALgADCgUJBQAAAA==.Cowpatty:BAAALgADCgYJEAAAAA==.',
Cu='Cuchi:BAAALgADCgkJDAAAAA==.Cutename:BAAALgAECgIJAgAAAA==.',
Cy='Cyraea:BAAALgAECgIJBQAAAA==.',
Cz='Czeskilight:BAABLgAECn8aAAIEAAgJ3A5fFgA+AQAEAAgJ3A5fFgA+AQAAAA==.',
['Câ']='Câl:BAAALgADCgUJBQAAAA==.',
['Cå']='Cåle:BAAALgAECgUJCQAAAA==.',
Da='Daane:BAAALgAECgEJAQAAAA==.Dabadwarrior:BAABLgAECn8hAAITAAgJogz5FACMAQATAAgJogz5FACMAQAAAA==.Dabs:BAAALgAECgEJAQAAAA==.Dabzilla:BAAALgAECgQJBAABLgAECggJHQAYAJgbAA==.Dabzîlla:BAAALgADCggJDAABLgAECggJHQAYAJgbAA==.Daffadill:BAAALgADCgEJAQAAAA==.Dakhran:BAAALgADCgUJFAAAAA==.Danero:BAAALgAECgEJAQAAAA==.Darkchangu:BAAALgAECgMJAwAAAA==.Darkdemon:BAABLgAECn8VAAIZAAYJFBMtLgArAQAZAAYJFBMtLgArAQAAAA==.Darknessz:BAAALgADCgcJDQAAAA==.Darkovia:BAAALgADCgMJAwAAAA==.',
De='Deagle:BAACLgAFFH8JAAIGAAQJRRjpBgBfAQAGAAQJRRjpBgBfAQAuAAQKfzAAAgYACAkwJDgBAOgCAAYACAkwJDgBAOgCAAAA.Deedubbya:BAAALgADCgMJAwAAAA==.Defense:BAAALgADCgkJFgAAAA==.Demonfrog:BAABLgAECn8eAAIIAAgJVhbUKACZAQAIAAgJVhbUKACZAQAAAA==.Desideria:BAAALgAECgYJEwAAAA==.Desynn:BAABLgAECn8eAAIPAAcJdBMXLQB4AQAPAAcJdBMXLQB4AQAAAA==.Deyndel:BAABLgAECn8WAAIDAAYJDgbrvwAHAQADAAYJDgbrvwAHAQAAAA==.',
Di='Divinesyn:BAAALgAECgYJCQAAAA==.',
Dj='Djtaki:BAABLgAECn8ZAAMGAAcJFxfYCwCrAQAGAAcJFxfYCwCrAQAHAAEJXA+PHQA/AAAAAA==.',
Do='Dobs:BAABLgAECn8XAAIaAAgJ/xhACAAqAgAaAAgJ/xhACAAqAgAAAA==.Dogwater:BAABLgAECn8YAAMWAAgJuhujBADKAgAWAAgJuhujBADKAgAOAAEJOQxcjAAvAAABLgAFFAQJBgAbAPobAA==.Domimpatrix:BAAALgADCgYJBgAAAA==.Doncarlos:BAAALgAECgUJCQAAAA==.Dorn:BAAALgADCgQJBAAAAA==.Dotsonly:BAAALgAECgYJCgAAAA==.Dotty:BAAALgAECgIJBAAAAA==.Downbeatxo:BAECLgAFFH8TAAMPAAYJHBzyAgDWAQAPAAYJHBzyAgDWAQAcAAEJSBXLFABVAAAuAAQKfyYAAw8ACQknJDwLACEDAA8ACAknJDwLACEDABwAAgnUHC5OAIMAAAAA.',
Dr='Dracow:BAAALgADCgkJEgABLgAECgcJEgACAAAAAA==.Dragonflash:BAABLgAECn8VAAMJAAgJgA01HwClAQAJAAgJgA01HwClAQAOAAEJAACjnAAEAAAAAA==.Droodormi:BAAALgADCgUJBQAAAA==.',
Du='Dubdred:BAAALgAECgMJBAABLgAECgYJGgAYAMYZAA==.Duberrok:BAABLgAECn8aAAMYAAYJxhlNFACzAQAYAAYJxhlNFACzAQADAAMJxQ1B+wCdAAAAAA==.Dunes:BAAALgAECgQJBAAAAA==.Dunidane:BAAALgADCgYJBgAAAA==.Durk:BAAALgAECgUJCQAAAA==.Durkk:BAAALgAECgUJBQAAAA==.',
Dw='Dwarfskin:BAAALgADCgQJBQAAAA==.Dwín:BAABLgAECn8YAAMJAAgJ/QXnNgA2AQAJAAgJ/QXnNgA2AQAOAAEJ+QB8mgAYAAAAAA==.',
Ea='Earthstalker:BAAALgAECgYJBgAAAA==.',
Ek='Ekzykes:BAAALgAECgIJAgAAAA==.',
El='Elasper:BAAALgAECgQJBwAAAA==.Eleathis:BAAALgADCggJJgAAAA==.',
Em='Emotionalism:BAAALgAECgYJBgAAAA==.Emäcs:BAAALgADCgIJAgAAAA==.',
En='Enjin:BAABLgAECn8ZAAIWAAgJPR+pBgCSAgAWAAgJPR+pBgCSAgAAAA==.Enragedbeef:BAABLgAECn8UAAMDAAYJFRK9jABiAQADAAYJFRK9jABiAQAYAAQJ1g0yawDNAAABLgAECggJGwAPAN4XAA==.Entheogen:BAAALgAECgcJDAAAAA==.',
Er='Erahlon:BAAALgADCgkJHQAAAA==.Eralak:BAAALgADCgIJAgAAAA==.Ereckshaun:BAAALgADCgQJAQAAAA==.Eree:BAAALgAECgMJBAAAAA==.Erinora:BAAALgAECgEJAQABLgAFFAMJBgARAI4RAA==.Ermoonsia:BAAALgADCgcJDAAAAA==.Erolas:BAAALgAECgIJAgAAAA==.',
Ev='Evanessance:BAAALgADCggJFQAAAA==.Evoka:BAABLgAECn8UAAIdAAcJDAdwEAD2AAAdAAcJDAdwEAD2AAAAAA==.Evopunkt:BAAALgAECgUJBgAAAA==.',
Fa='Faavimonk:BAABLgAECn8WAAIUAAYJgRNWMQBgAQAUAAYJgRNWMQBgAQAAAA==.Fallendevout:BAAALgADCgkJFQAAAA==.Fallendots:BAAALgADCgUJCQAAAA==.Fallenseer:BAABLgAECn8XAAIeAAYJbBoyOwBhAQAeAAYJbBoyOwBhAQAAAA==.Fallentroll:BAAALgAFFAIJAgAAAA==.Fatman:BAAALgAECgUJCgAAAA==.Faydark:BAAALgAECgQJBAAAAA==.Fayia:BAAALgADCgkJIAAAAA==.Fayye:BAAALgAECgQJBwAAAA==.',
Fe='Feliandril:BAAALgAECgEJAQAAAA==.Fellin:BAABLgAECn8hAAMOAAgJkQaPCQA8AQAOAAgJzwWPCQA8AQAJAAcJ4AQqUADcAAAAAA==.Femto:BAACLgAFFH8LAAIIAAMJSCV6JgAjAQAIAAMJSCV6JgAjAQAuAAQKfzIAAggACAnAI0caAN8CAAgACAnAI0caAN8CAAAA.',
Fi='Fiestyrae:BAAALgADCgYJBgAAAA==.Fintrollz:BAAALgAECgQJBAAAAA==.Fiorina:BAAALgAECgEJAQABLgAECgYJGgAfAOEVAA==.Fireburd:BAAALgADCgYJCgAAAA==.Firèflyjd:BAAALgAECgYJCgAAAA==.Fishersam:BAAALgADCgYJBgAAAA==.Fishy:BAAALgADCgkJDwAAAA==.',
Fl='Flintzombie:BAAALgADCgkJCQABLgAECggJIAAXAKQQAA==.Floatpass:BAABLgAECn8cAAIMAAgJnht7GQATAgAMAAgJnht7GQATAgAAAA==.Floweranjel:BAAALgADCgYJEAAAAA==.Fluffymyone:BAABLgAECn8ZAAIMAAcJdwFmkgCrAAAMAAcJdwFmkgCrAAAAAA==.',
Fo='Foghat:BAAALgADCgcJCgAAAA==.Fongsiyuk:BAABLgAECn8XAAIUAAYJRREUGQAeAQAUAAYJRREUGQAeAQAAAA==.Foxhammer:BAAALgADCgcJBwAAAA==.',
Fr='Freezeberry:BAAALgAECgEJAgAAAA==.Froey:BAAALgADCgQJBAAAAA==.Froeyglaive:BAAALgAECgQJCAAAAA==.',
Fu='Furlog:BAAALgADCgYJBwAAAA==.Fuzz:BAAALgADCgIJAgAAAA==.Fuzzymonk:BAAALgAECgcJDAAAAA==.Fuzzytotems:BAABLgAFFH8KAAIKAAQJ3RoXCgBHAQAKAAQJ3RoXCgBHAQAAAA==.',
['Fá']='Fáavi:BAAALgADCgQJBAABLgAECgkJFgAUAIETAA==.',
Ga='Gabagooly:BAAALgAECgMJAwAAAA==.Gali:BAACLgAFFH8MAAMJAAMJWRDtDQDoAAAJAAMJNg/tDQDoAAAOAAMJOAZfDACpAAAuAAQKfy0ABAkACAkjHnUOAMgCAAkACAniHXUOAMgCAA4ACAkjFGg6AHUBABYAAQkBFnAsAEUAAAAA.Galiagante:BAAALgADCgcJEQAAAA==.Galiashammy:BAAALgADCgUJBQABLgADCgcJEQACAAAAAA==.Gallynna:BAABLgAECn8gAAQPAAgJARSIQwAmAQAPAAUJ/g2IQwAmAQAcAAUJwhOsNADkAAAQAAMJShSdCgCIAAAAAA==.Galorfax:BAABLgAECn8UAAIaAAYJ3xhICQBAAQAaAAYJ3xhICQBAAQAAAA==.Galorfox:BAAALgADCgUJBQAAAA==.Galushi:BAAALgAECgIJAgAAAA==.Gamervato:BAAALgAECgIJAgAAAA==.Gannondalf:BAAALgADCgUJBQABLgAECggJIAAXAKQQAA==.Garlic:BAAALgAECgMJBQAAAA==.Garm:BAABLgAECn8VAAIJAAcJwxh7IwCOAQAJAAcJwxh7IwCOAQAAAA==.',
Ge='Gelinea:BAAALgAECgQJCgAAAA==.Genovese:BAAALgAECgkJCgAAAA==.Gerardbutler:BAAALgADCgkJCQAAAA==.Geyboy:BAAALgAECgEJAgAAAA==.',
Gi='Gilgameshx:BAAALgADCgIJAgAAAA==.Gilgaroth:BAABLgAECn8aAAMGAAgJ0hVCIgDnAQAGAAcJOBhCIgDnAQAHAAIJOQsvEABjAAAAAA==.Girdlin:BAAALgADCgcJEgAAAA==.Girlslove:BAAALgADCgMJAwABLgAFFAQJBgAbAPobAA==.',
Gl='Glaucoma:BAAALgAECgQJBAAAAA==.',
Go='Gobo:BAAALgAECgMJAwABLgAECggJGAAFAE0SAA==.Gorendish:BAAALgADCggJBwAAAA==.',
Gr='Graevus:BAABLgAECn8jAAIgAAgJFRgpIQA7AgAgAAgJFRgpIQA7AgAAAA==.Graku:BAAALgAECgkJCAAAAA==.Graysonn:BAAALgADCgkJFgAAAA==.Greyheart:BAAALgADCgUJBQAAAA==.Grimmora:BAAALgADCgYJCgAAAA==.Grëybeard:BAABLgAECn8ZAAISAAgJKRNXBQDWAQASAAgJKRNXBQDWAQAAAA==.',
Gu='Gundrakk:BAACLgAFFH8FAAIgAAMJGgyFGwDBAAAgAAMJGgyFGwDBAAAuAAQKfyQAAiAACAmBH/YLAEkCACAACAmBH/YLAEkCAAAA.Gunnr:BAAALgAECgQJBAABLgAECgUJDQACAAAAAA==.Gunthorian:BAABLgAECn8bAAMDAAgJEAxFPwBMAQADAAgJEAxFPwBMAQAYAAYJWg/dTABFAQAAAA==.',
Ha='Hame:BAAALgADCgMJAwAAAA==.Hamme:BAAALgADCgEJAQAAAA==.Handsomemonk:BAABLgAECn8gAAQhAAgJ8RahDgC9AQAhAAcJqBehDgC9AQAiAAYJehXpSQAbAQAUAAQJjQ8+XACfAAAAAA==.Hangvhul:BAABLgAECn8YAAINAAgJ0w7aDQDfAQANAAgJ0w7aDQDfAQAAAA==.Hansi:BAAALgAECgQJCAAAAA==.Harkonnen:BAABLgAECn8iAAMPAAgJSgw7MABqAQAPAAgJRws7MABqAQAcAAEJ+ROucQA0AAAAAA==.',
He='Healmme:BAAALgAECgUJBQAAAA==.Heart:BAAALgAECgMJBgABLgAECgMJBgACAAAAAA==.Hectic:BAAALgADCgMJAwABLgAECggJHQAYAJgbAA==.Heid:BAAALgAECgIJAgAAAA==.Helianna:BAAALgAFFAMJAwABLgAFFAUJDgAJAHQQAA==.Helldozer:BAAALgAECgMJBgAAAA==.',
Hi='Himejoshi:BAACLgAFFH8GAAIbAAQJ+hsoAgAmAQAbAAQJ+hsoAgAmAQAuAAQKfx4AAxsACAmOJGYBAFwDABsACAmOJGYBAFwDABoABwkVHuQFAHUCAAAA.Hirys:BAAALgAFFAEJAQAAAA==.',
Ho='Holybanana:BAAALgAECgYJEwAAAA==.Holymerble:BAAALgAECgEJAQABLgAECgcJDgACAAAAAA==.Holyramen:BAAALgADCgcJBwAAAA==.Horsewing:BAAALgAECgYJEAAAAA==.Hotdoggin:BAAALgAECgQJBAAAAA==.Hotmerble:BAAALgAECgcJDgAAAA==.Hotshotzz:BAAALgAECgQJBgABLgAFFAMJBAACAAAAAA==.Hotstreak:BAAALgAFFAMJBAAAAA==.',
Hu='Huntsmedown:BAAALgAECgIJAgAAAA==.',
Hy='Hyjali:BAAALgADCgEJAQAAAA==.',
['Há']='Háldrin:BAACLgAFFH8OAAQJAAUJdBCGCwAGAQAJAAQJUQ6GCwAGAQAWAAQJZQW3CwDgAAAOAAIJDA1KIACUAAAuAAQKfxYAAw4ACAkCGrIcAD8CAA4ACAkCGrIcAD8CABYABAndEpgUACUBAAAA.',
['Hä']='Härmacist:BAAALgAECgUJBQAAAA==.',
Il='Illexi:BAAALgADCgYJBgAAAA==.Ilthunis:BAAALgADCgcJEAAAAA==.',
Im='Imadruîd:BAAALgAECgQJBQAAAA==.Imbue:BAABLgAECn8WAAIjAAYJBCCjBgAlAgAjAAYJBCCjBgAlAgAAAA==.Immortals:BAAALgAECgQJBQAAAA==.Imthatguyy:BAAALgAECgMJAwAAAA==.',
In='Innil:BAAALgAFFAEJAQAAAA==.',
Ip='Ipunch:BAAALgAECgQJCAAAAA==.',
Is='Isimiel:BAAALgADCgQJBAAAAA==.',
Ja='Jaesa:BAAALgADCgEJAQAAAA==.Jainiia:BAAALgAECgcJBgAAAA==.',
Je='Jessiks:BAAALgADCgEJAQAAAA==.Jetlisa:BAAALgADCgcJBwAAAA==.Jezebel:BAABLgAECn8ZAAMPAAgJsAmHQwAmAQAPAAcJigqHQwAmAQAcAAEJlgRmJAAkAAAAAA==.',
Ji='Jiaoe:BAAALgADCgQJBAAAAA==.Jinxing:BAAALgAECgMJAwAAAA==.Jinze:BAAALgAECgEJAQAAAA==.Jirito:BAAALgADCgcJBwABLgAECggJEwACAAAAAA==.Jirto:BAAALgAECggJEwAAAA==.',
Jo='Jomadead:BAABLgAECn8VAAILAAcJjhYxDwAhAQALAAcJjhYxDwAhAQABLgAFFAUJEwAKACUPAA==.Jomadh:BAAALgADCgEJAQAAAA==.Jomadin:BAAALgAECgEJAQABLgAFFAUJEwAKACUPAA==.Jomage:BAAALgADCgcJBwABLgAFFAUJEwAKACUPAA==.Jomar:BAAALgAECgQJBQAAAA==.Jomas:BAACLgAFFH8TAAMKAAUJJQ+ICABeAQAKAAUJJQ+ICABeAQAeAAEJWgWvJABDAAAuAAQKfygAAwoACQkPH+YHAPYCAAoACQkPH+YHAPYCAB4ABQkLILwxAJUBAAAA.',
Ju='Jubbjubb:BAACLgAFFH8IAAIMAAQJjQmqJwAyAQAMAAQJjQmqJwAyAQAuAAQKfygAAgwACQn2Hoo0AKECAAwACQn2Hoo0AKECAAAA.Judera:BAABLgAECn8XAAIDAAcJ0Bb7NwBkAQADAAcJ0Bb7NwBkAQAAAA==.Jugful:BAAALgAECgEJAQAAAA==.Juicemoose:BAAALgAECgYJEgAAAA==.Juicybooty:BAAALgADCgUJBQAAAA==.Justokelf:BAABLgAECn8WAAIZAAcJAh+iFwCrAQAZAAcJAh+iFwCrAQAAAA==.',
Jw='Jwarr:BAAALgADCgEJAQAAAA==.',
Ka='Kagura:BAAALgADCgcJBwAAAA==.Kaiden:BAAALgADCggJFgAAAA==.Kaing:BAAALgAECgYJEAAAAA==.Kainlithia:BAAALgAECgYJCQAAAA==.Kaladen:BAAALgAECgEJAwAAAA==.Kalindica:BAAALgADCgYJBgAAAA==.Kalysti:BAAALgAECgYJGgAAAQ==.Kandee:BAAALgAECgYJEQAAAA==.Karkonas:BAAALgADCgEJAQABLgAECgcJEAACAAAAAA==.Karliahdark:BAAALgAECgMJAwAAAA==.Karolg:BAAALgAECgQJBAAAAA==.Karuli:BAAALgADCgkJIgAAAA==.Karvis:BAAALgAECgUJDgAAAA==.Kasuri:BAAALgAECgEJAgAAAA==.Katostrafic:BAAALgAECgYJEAAAAA==.Kazemage:BAABLgAECn8XAAMBAAgJfg/8AQC9AQABAAgJfg/8AQC9AQAMAAEJJgKj6AAmAAAAAA==.',
Ke='Kevais:BAAALgADCgQJBwAAAA==.',
Kh='Khromscarin:BAABLgAECn8pAAIjAAgJUR8bAwCvAgAjAAgJUR8bAwCvAgAAAA==.',
Ki='Kiaradarkpaw:BAAALgADCgEJAQAAAA==.Kielli:BAAALgADCgEJAQAAAA==.Killboi:BAAALgAECgMJBQAAAA==.Killidan:BAACLgAFFH8KAAIZAAQJexQmDwBAAQAZAAQJexQmDwBAAQAuAAQKfxkAAhkACAnqI4cRAPICABkACAnqI4cRAPICAAAA.Kimberllynn:BAAALgAECgcJBwAAAA==.Kiridus:BAABLgAECn8aAAMfAAYJ4RVxFgBMAQAfAAYJ4RVxFgBMAQAgAAEJoQTw4QAjAAAAAA==.Kirklees:BAAALgADCgUJCQAAAA==.',
Kl='Klaudiuss:BAAALgADCgYJBwAAAA==.',
Kn='Knackers:BAAALgADCggJDQAAAA==.',
Ko='Kodama:BAABLgAECn8eAAIeAAgJKQ2VGABOAQAeAAgJKQ2VGABOAQAAAA==.Koi:BAAALgADCgkJEAAAAA==.Kookiesplz:BAAALgADCgkJFAAAAA==.Kopili:BAAALgAECgQJCwAAAA==.Koryn:BAABLgAECn8SAAIRAAcJyArvNABDAQARAAcJyArvNABDAQAAAA==.Kotz:BAAALgAECgcJDgAAAA==.',
Kr='Kratina:BAAALgADCgEJAQAAAA==.Krunthe:BAAALgAECgQJBAAAAA==.Kryxis:BAAALgAECgYJBwAAAA==.',
Ku='Kunpochiken:BAAALgAECgQJBwABLgAECgYJEAACAAAAAA==.',
La='Lacrymos:BAABLgAECn8fAAIjAAgJaRjsAwDDAQAjAAgJaRjsAwDDAQAAAA==.Lader:BAAALgAECgkJCQAAAA==.Larril:BAAALgADCgYJBwAAAA==.Laurebeth:BAAALgADCgkJDQAAAA==.Laxinmedium:BAAALgAECgIJAgAAAA==.',
Le='Lesavatar:BAAALgADCgUJBQAAAA==.Levande:BAABLgAECn8XAAMkAAgJQxnuEgBIAgAkAAgJ5hjuEgBIAgAEAAUJ/Q2XMQAUAQAAAA==.',
Li='Lid:BAAALgADCgMJAwAAAA==.Lighttickle:BAAALgADCgMJAwAAAA==.Liling:BAAALgADCgEJAgABLgAECgYJCgACAAAAAA==.Lilithandria:BAAALgAECgcJEgAAAA==.Lilletth:BAAALgADCgUJBQAAAA==.Lilyola:BAAALgAECgYJDAAAAA==.Limabeanjr:BAAALgADCggJCAAAAA==.Linamar:BAAALgADCgkJKAAAAA==.Lisan:BAAALgAECgQJBAAAAA==.',
Lo='Loaq:BAACLgAFFH8HAAIEAAMJKQ4/EgDoAAAEAAMJKQ4/EgDoAAAuAAQKfx4AAgQACAlwHdMIAK8CAAQACAlwHdMIAK8CAAAA.Lockzrockz:BAAALgADCgcJDQAAAA==.Lorbert:BAAALgADCgcJBwABLgAECgcJIAATAOoXAA==.',
Lu='Luxæterna:BAABLgAECn8lAAIDAAgJ+RwtJgCNAgADAAgJ+RwtJgCNAgAAAA==.',
Ly='Lystrasza:BAAALgAECgYJEAAAAA==.Lyte:BAAALgADCgYJEAAAAA==.',
['Lí']='Líllìth:BAAALgADCgYJBgAAAA==.',
Ma='Madjekyll:BAAALgAECgEJAQABLgAECgYJFAATAGgjAA==.Magus:BAAALgAECgIJBAAAAA==.Maikeru:BAABLgAECn8YAAIlAAUJLBxtBABFAQAlAAUJLBxtBABFAQAAAA==.Maizy:BAAALgADCgIJAgAAAA==.Malduku:BAAALgADCgYJBgAAAA==.Malemenas:BAAALgADCgkJIwAAAA==.Malice:BAABLgAECn8jAAMQAAgJsx5lAQDfAgAQAAgJsx5lAQDfAgAPAAMJQQtXcgClAAAAAA==.Mandwandos:BAAALgAECgcJCQAAAA==.Maraliss:BAAALgAECgYJCgAAAA==.Marjon:BAAALgAECgYJDwAAAA==.Maroonfive:BAAALgAECgEJAgAAAA==.Marrash:BAAALgADCgcJBgAAAA==.Masashii:BAAALgADCgQJBAABLgADCgkJEAACAAAAAA==.Mastatea:BAAALgADCggJCgAAAA==.Matamoros:BAAALgADCgcJCAAAAA==.Maugrimm:BAAALgADCgkJEwAAAA==.Maxn:BAAALgADCgcJBwAAAA==.Maxrox:BAAALgAECgQJBAAAAA==.Mayalodu:BAAALgAECgQJEQAAAA==.',
Me='Melaunis:BAAALgAECgUJBgAAAA==.Mellwynn:BAAALgADCgMJAwAAAA==.Mellínna:BAAALgADCgYJCwAAAA==.Meora:BAAALgAECgIJAgABLgAFFAQJDgAXAGoTAA==.Meowelf:BAAALgADCgUJBQAAAA==.Meowow:BAAALgAECgYJDAAAAA==.Merks:BAAALgAFFAEJAQAAAA==.Metas:BAAALgAECgcJDQABLgAFFAQJDgAXAGoTAA==.Meteora:BAACLgAFFH8OAAIXAAQJahMdBgAmAQAXAAQJahMdBgAmAQAuAAQKfyMAAhcACQmHHpoIAJYCABcACQmHHpoIAJYCAAAA.',
Mh='Mhithrha:BAABLgAECn8UAAIfAAcJDRQVFABkAQAfAAcJDRQVFABkAQAAAA==.',
Mi='Migolbearcow:BAABLgAECn8iAAIaAAgJtBWVBQCuAQAaAAgJtBWVBQCuAQAAAA==.Miinx:BAAALgAECggJDwAAAA==.Minervamon:BAAALgADCgMJAwAAAA==.Minotauren:BAAALgAECgMJAwAAAA==.Missed:BAABLgAECn8cAAIDAAgJFiPYBgCtAgADAAgJFiPYBgCtAgAAAA==.Missedweaver:BAAALgAECggJDQABLgAECggJHAADABYjAA==.Miyuni:BAAALgADCgMJAwAAAA==.',
Ml='Mlglock:BAABLgAECn8XAAIPAAkJ6hs7IgCMAgAPAAkJ6hs7IgCMAgAAAA==.',
Mo='Mongocrush:BAAALgADCggJFQAAAA==.Monyshot:BAAALgADCgEJAQAAAA==.Moocifur:BAAALgADCgkJEgAAAA==.Moonbeary:BAAALgAECgcJBwAAAA==.Mooniè:BAAALgAECgYJCgAAAA==.Moosenuts:BAAALgADCgMJAwAAAA==.Moxxii:BAABLgAECn8WAAMLAAgJlhz2DwANAgALAAYJmiD2DwANAgAIAAMJjg8+5wCxAAAAAA==.',
Mu='Muradigme:BAAALgAECgMJAwAAAA==.Mushufasa:BAAALgADCgQJBAAAAA==.Mutilusgore:BAABLgAECn8gAAIXAAgJpBA4DABgAQAXAAgJpBA4DABgAQAAAA==.',
My='Myshella:BAAALgAECgYJCgAAAA==.Myylus:BAAALgADCggJCgAAAA==.',
['Mö']='Mökes:BAACLgAFFH8GAAIcAAMJvxw0AgAcAQAcAAMJvxw0AgAcAQAuAAQKfxgAAhwACAl6IVQBABkDABwACAl6IVQBABkDAAAA.',
Na='Naijin:BAAALgADCgEJAQABLgAECgYJCgACAAAAAA==.Nasana:BAAALgADCgQJBAAAAA==.Navarra:BAAALgADCgEJAQAAAA==.Nawzero:BAAALgAECgEJAQAAAA==.Nax:BAAALgAECgEJBQAAAA==.Nazagos:BAAALgAECgcJBwABLgAECgkJIQAJAPckAA==.Nazeiro:BAABLgAECn8RAAIZAAYJShDIeAA8AQAZAAYJShDIeAA8AQAAAA==.Nazzersaurus:BAAALgAECgYJEAAAAA==.',
Ne='Negies:BAAALgADCgYJBgAAAA==.Nekestinea:BAAALgADCgIJAgAAAA==.Nekomata:BAABLgAECn8VAAIfAAYJrBIGGgAsAQAfAAYJrBIGGgAsAQAAAA==.Nekosmasta:BAAALgADCggJCAAAAA==.Neodin:BAAALgADCgkJKAAAAA==.Newhamme:BAAALgAECgUJBQAAAA==.',
Ni='Nightjewel:BAAALgAECgIJAgAAAA==.',
No='Noctevera:BAAALgADCgkJEQAAAA==.Noggs:BAAALgAECgEJAQAAAA==.Nokawa:BAAALgADCgYJBgAAAA==.Nokkas:BAAALgAECgcJBwAAAA==.Novadisc:BAAALgADCggJCAAAAA==.',
Nu='Nuali:BAAALgADCgkJEQABLgAECggJIAAkAAQaAA==.Numbers:BAABLgAECn8bAAIYAAkJDByyCADkAgAYAAkJDByyCADkAgAAAA==.',
['Nê']='Nêrtt:BAABLgAECn8pAAMmAAgJWR3vBQCYAgAmAAcJkh/vBQCYAgAdAAgJqxeABAArAgAAAA==.',
Oc='Oche:BAAALgADCgcJDgABLgAECgYJEAACAAAAAA==.',
Ok='Oketra:BAAALgADCgUJBQAAAA==.',
Om='Omniia:BAAALgAECgMJAwAAAA==.',
On='Onedog:BAAALgADCgEJAQAAAA==.Ontera:BAAALgAECgYJCgAAAA==.',
Or='Orala:BAABLgAECn8YAAIRAAYJuxYTFABiAQARAAYJuxYTFABiAQAAAA==.Orý:BAABLgAECn8wAAIeAAkJyh5sAgDEAgAeAAkJyh5sAgDEAgAAAA==.',
Os='Oslatem:BAAALgAECgQJCAAAAA==.',
Ot='Ottrekker:BAAALgADCgIJAgABLgAECgcJDgACAAAAAA==.',
Ov='Overlie:BAAALgADCgIJAgAAAA==.',
Ox='Oxosorrel:BAAALgAECgEJAQAAAA==.',
Pa='Paladan:BAACLgAFFH8KAAMDAAQJjhu+CABvAQADAAQJjhu+CABvAQAnAAEJ+xNwBwA9AAAuAAQKfxgAAwMACAloJWcLADMDAAMACAkkJWcLADMDACcABgmMI98IAEgCAAAA.Paladeez:BAAALgAECgQJBAAAAA==.Palyboye:BAAALgADCgQJBAAAAA==.Pamorlin:BAAALgAECgEJAgAAAA==.Pandamonea:BAAALgADCggJDgABLgAECgIJAgACAAAAAA==.Pandamonium:BAAALgADCgYJCQABLgAECgIJAgACAAAAAA==.Pandapunkt:BAAALgAECgYJCgAAAA==.Pandragon:BAAALgAECgIJAgAAAA==.Parallax:BAAALgAECgIJAgAAAA==.Parishealton:BAABLgAECn8kAAIgAAgJrB85BQDPAgAgAAgJrB85BQDPAgAAAA==.Pastybeard:BAABLgAECn8fAAMQAAgJ9SHXAgCFAgAQAAgJPCHXAgCFAgAPAAgJhRs9DABRAgAAAA==.Pazzuzu:BAAALgADCgkJEgAAAA==.',
Pe='Penjamin:BAAALgAECgUJCQAAAA==.Pewnani:BAAALgADCgMJAwAAAA==.',
Ph='Phaestos:BAAALgAECgMJAwABLgAECgYJGgAfAOEVAA==.',
Pi='Pinkburrito:BAAALgADCgEJAQAAAA==.',
Pl='Planetes:BAAALgAECgIJBAAAAA==.',
Po='Pontar:BAAALgAECgYJBgAAAA==.Pordobel:BAAALgADCgEJAQAAAA==.Portalnugget:BAAALgAECgEJAQABLgAFFAMJBQAgABoMAA==.Portalz:BAAALgADCgYJBwABLgAECggJHAADABYjAA==.',
Pr='Prominence:BAABLgAECn8YAAIOAAcJvRzbBAC3AQAOAAcJvRzbBAC3AQAAAA==.Proy:BAAALgAECgcJCgAAAA==.Prozak:BAABLgAECn8dAAIKAAgJyxftCwAsAgAKAAgJyxftCwAsAgAAAA==.',
Ps='Psychofrenic:BAAALgADCgYJCQABLgAECggJHgATAPsZAA==.',
Pu='Puhlayden:BAABLgAECn8XAAMDAAgJax7rOAA/AgADAAcJ0B7rOAA/AgAYAAcJCQqERQBiAQAAAA==.',
['Pò']='Pòppy:BAAALgADCgcJBwAAAA==.',
Qu='Quikanez:BAAALgAECgYJEAAAAA==.Qulung:BAAALgADCgkJCQAAAA==.',
Ra='Rabyd:BAAALgAECgIJAwAAAA==.Radmane:BAAALgADCgEJAQAAAA==.Raegasm:BAAALgADCgQJBQAAAA==.Raein:BAAALgAECgQJBwAAAA==.Raithe:BAAALgADCgQJBAAAAA==.Raskela:BAABLgAECn8XAAIhAAgJmRwDDgB1AgAhAAgJmRwDDgB1AgAAAA==.Raskella:BAAALgAECgEJAQABLgAECggJFwAhAJkcAA==.Ratboy:BAABLgAECn8eAAMGAAgJahl5DwCtAgAGAAgJahl5DwCtAgAHAAEJ2g7UIAAuAAAAAA==.Ratkiss:BAAALgADCgYJBgAAAA==.',
Re='Reckhn:BAAALgADCgYJBgAAAA==.Reprieve:BAAALgAECgYJEwAAAA==.Retradormi:BAAALgADCgMJAwAAAA==.Reversal:BAAALgAECgYJBgABLgAECggJHgATAPsZAA==.Rexe:BAABLgAFFH8HAAMOAAMJZQPsCgDCAAAOAAMJZQPsCgDCAAAJAAEJawGgLQBAAAAAAA==.Rexy:BAAALgAECgYJBwABLgAFFAMJBwAOAGUDAA==.',
Rh='Rhane:BAAALgAECgYJDgAAAA==.Rhazputin:BAAALgAECgQJBQAAAA==.Rhend:BAAALgADCgcJBwAAAA==.',
Ri='Riang:BAAALgADCgcJBwAAAA==.Rickcando:BAAALgAECgQJCgAAAA==.Ricshard:BAABLgAECn8bAAMcAAcJyRhYCQASAQAPAAQJMxdqRAAkAQAcAAUJIhdYCQASAQAAAA==.Ridjeckgron:BAAALgAECgMJBAAAAA==.Righteouskat:BAAALgADCgIJAgAAAA==.Rinea:BAABLgAECn8gAAMkAAgJBBrbCAAbAgAkAAgJBBrbCAAbAgARAAEJ6gRlZgAsAAAAAA==.Riserphenex:BAAALgADCgkJCQABLgAFFAQJCQAGAEUYAA==.Risse:BAAALgAECgYJEAAAAA==.',
Ro='Roarkitty:BAAALgAECgUJDAAAAA==.Rocknaw:BAABLgAECn8UAAIDAAgJqxjMHgDRAQADAAgJqxjMHgDRAQAAAA==.Rodgers:BAAALgAECgYJBgABLgAFFAQJDgAXAGoTAA==.Rogaldorne:BAAALgAECgYJCQAAAA==.Romans:BAAALgADCgcJDwABLgAECgkJGwAYAAwcAA==.Ronicary:BAAALgADCgYJAwAAAA==.Roofeed:BAAALgADCgEJAQAAAA==.Rospeteal:BAABLgAECn8lAAIcAAgJAxQfBACfAQAcAAgJAxQfBACfAQAAAA==.',
Ru='Ruben:BAAALgADCgYJCAAAAA==.Runefnar:BAAALgADCgkJEwAAAA==.Rungar:BAAALgADCgQJBAAAAA==.',
Ry='Rydmytotem:BAAALgADCgcJEwAAAA==.Rylia:BAAALgAECgMJAwAAAA==.Ryuhari:BAABLgAECn8cAAIaAAgJsR+kAQB3AgAaAAgJsR+kAQB3AgAAAA==.Ryujin:BAABLgAECn8eAAMGAAgJdxBKCwC0AQAGAAgJcA5KCwC0AQAHAAYJKAscCAAcAQAAAA==.',
['Ró']='Ród:BAAALgAFFAEJAQABLgAFFAMJBAACAAAAAA==.',
Sa='Saalira:BAAALgAECgIJAgAAAA==.Sabellice:BAABLgAECn8bAAIDAAcJTRHpQQBEAQADAAcJTRHpQQBEAQAAAA==.Sadicia:BAAALgADCgIJAwAAAA==.Sakonna:BAABLgAFFH8GAAIRAAMJjhHPDgDVAAARAAMJjhHPDgDVAAAAAA==.Salinoria:BAAALgADCgkJCQABLgAECggJIAAkAAQaAA==.Saltyfingers:BAAALgADCggJCAAAAA==.Samwell:BAAALgADCgkJEQAAAA==.Saniroin:BAAALgADCgIJAgAAAA==.Sarlius:BAABLgAECn8hAAIJAAkJ9yTBAAC5AwAJAAkJ9yTBAAC5AwAAAA==.Savin:BAAALgAECgYJCgAAAA==.',
Sc='Scargrimm:BAAALgAECgcJBgAAAA==.Scavenger:BAAALgAECgYJBgAAAA==.Schorsha:BAAALgAECgQJCQAAAA==.',
Se='Selkamonk:BAABLgAECn8gAAMhAAgJOiIbAgABAwAhAAgJOiIbAgABAwAUAAEJAACVdQBAAAAAAA==.Seniorbold:BAAALgAECgQJBgAAAA==.Sentrina:BAACLgAFFH8FAAIdAAQJtAa0DAAGAQAdAAQJtAa0DAAGAQAuAAQKfygAAh0ACQloGNUPAD0CAB0ACQloGNUPAD0CAAAA.Seramon:BAAALgADCgQJBAABLgAECggJGQAWAD0fAA==.Seraph:BAAALgAECgEJAgAAAA==.Serenìty:BAAALgADCgIJAwAAAA==.Seshy:BAAALgAECgQJDwABLgAECggJGwAPAN4XAA==.Seshymutedme:BAABLgAECn8bAAQPAAgJ3heMJQCZAQAPAAcJ3heMJQCZAQAcAAQJkAowOQDQAAAQAAEJAADbNwAfAAAAAA==.',
Sh='Shadian:BAAALgADCgIJAgAAAA==.Shamanagins:BAAALgAECgIJAgAAAA==.Shannon:BAAALgADCgcJBwABLgAECgQJBwACAAAAAA==.Shannoon:BAAALgAECgQJBwAAAA==.Shimmiiee:BAAALgAECgYJCAAAAA==.Shing:BAABLgAECn8fAAMiAAkJBBkMGABEAgAiAAcJzB0MGABEAgAUAAUJ2A0jSwDlAAAAAA==.Shiverr:BAAALgADCgkJGQAAAA==.Shoftìel:BAAALgADCgcJCgAAAA==.Shxt:BAAALgADCgIJAgAAAA==.',
Si='Sivrak:BAAALgADCgUJAgAAAA==.',
Sk='Skizem:BAAALgADCgIJAgAAAA==.Skott:BAAALgAECgEJAgAAAA==.',
Sl='Sleepadin:BAAALgAECgUJBQAAAA==.Sleepyr:BAABLgAECn8dAAIFAAgJsgtuKQBzAQAFAAgJsgtuKQBzAQAAAA==.Slobkabob:BAAALgAECgEJAwAAAA==.',
Sm='Smol:BAAALgAECgMJBgAAAA==.Smolside:BAAALgADCgEJAQAAAA==.',
Sn='Snowi:BAAALgADCgEJAQABLgAECgUJDQACAAAAAA==.',
So='Solignis:BAACLgAFFH8YAAMTAAYJ1yF2AQDvAQATAAUJNCF2AQDvAQASAAEJYySyDQBvAAAuAAQKfzkAAxMACQlDJsYAANUDABMACQlDJsYAANUDABIAAQm1IwUjAGMAAAAA.Soohots:BAAALgAECgUJCgAAAA==.Soular:BAAALgADCgMJAwAAAA==.',
Sp='Sparklehappy:BAAALgAECgUJCgAAAA==.Spiritdurk:BAAALgADCggJDAAAAA==.Spoghasm:BAABLgAECn8XAAIaAAcJLyNtAwAMAgAaAAcJLyNtAwAMAgAAAA==.Spothoof:BAACLgAFFH8OAAIeAAQJVxNgCgA7AQAeAAQJVxNgCgA7AQAuAAQKfyMAAh4ACQmmH7YMANICAB4ACQmmH7YMANICAAAA.Spyreaux:BAAALgADCgYJBgAAAA==.',
St='Stalari:BAAALgAECgcJCwAAAA==.Starshield:BAAALgADCgQJBAABLgAECgYJEgACAAAAAA==.Stcupertino:BAABLgAECn8YAAMYAAgJtQU5IABFAQAYAAgJtQU5IABFAQADAAEJzwXaVQEoAAAAAA==.Steamedham:BAAALgAECgcJBwAAAA==.Steeljustice:BAAALgADCgcJDAAAAA==.Stellalou:BAAALgAECgEJAgAAAA==.Stormstout:BAAALgADCgIJAgAAAA==.Storri:BAABLgAECn8bAAIkAAYJ2hUbFgBdAQAkAAYJ2hUbFgBdAQAAAA==.Stryranger:BAAALgAECgUJBQAAAA==.',
Su='Submersed:BAAALgADCgYJBgAAAA==.Suehunter:BAAALgADCgcJDwAAAA==.Suturi:BAAALgADCggJCAAAAA==.Suvi:BAAALgADCgEJBAAAAA==.Suzuya:BAAALgADCgcJIQAAAA==.',
Sw='Swiftly:BAAALgAFFAIJAgAAAA==.Swiftmage:BAACLgAFFH8YAAIMAAYJeCGbAgARAgAMAAYJeCGbAgARAgAuAAQKfzgAAgwACQmHJn0AAIQDAAwACQmHJn0AAIQDAAAA.',
Sy='Sylvian:BAAALgAECgQJBgAAAA==.Syndrome:BAAALgAECgYJEgAAAA==.Syrelea:BAAALgADCgIJAgAAAA==.',
Sz='Szeto:BAAALgAECgUJDQAAAA==.',
Ta='Talyndis:BAACLgAFFH8XAAMOAAcJbBwHBAD/AQAOAAcJDBsHBAD/AQAJAAIJQiObIADJAAAuAAQKfx8AAw4ACQnFIxoDAHcDAA4ACQmmIhoDAHcDAAkAAglQF1hjAJ4AAAAA.Tamyr:BAAALgADCgMJAwABLgAECgEJAQACAAAAAA==.Tashido:BAAALgAECgQJBAAAAA==.Taze:BAAALgAECgQJBAABLgAFFAMJDAAJAFkQAA==.Tazjiingo:BAAALgAECgQJBwAAAA==.',
Te='Teanie:BAAALgADCgYJBgAAAA==.Tenebrium:BAAALgAECgEJAwAAAA==.Terhali:BAAALgAECgUJBQAAAA==.Terrika:BAAALgAECgYJDgAAAA==.Tetshajeh:BAAALgAECgYJEQAAAA==.',
Th='Theanimal:BAAALgADCgcJCAAAAA==.Therasa:BAAALgAECgEJAQAAAA==.Thewizardguy:BAAALgAECgUJBwAAAA==.Thillarick:BAABLgAECn8UAAITAAYJaCNgCgAEAgATAAYJaCNgCgAEAgAAAA==.Thiss:BAAALgADCgkJCgAAAA==.Thiya:BAABLgAECn8VAAIDAAcJDQ32QQBEAQADAAcJDQ32QQBEAQAAAA==.Thorvard:BAAALgAECgUJEAAAAA==.Thromanor:BAAALgAECgIJAgAAAA==.',
Ti='Tirachill:BAAALgAECgEJAQAAAA==.Tiramisú:BAAALgAECgQJBgAAAA==.Tiranmyashol:BAABLgAECn8gAAITAAcJ6heWLwDxAQATAAcJ6heWLwDxAQAAAA==.',
To='Toothdk:BAAALgAECgUJEwAAAA==.Toppo:BAABLgAECn8bAAInAAgJWyEBAwBBAgAnAAgJWyEBAwBBAgAAAA==.Torfnar:BAAALgAECgYJDAAAAA==.Toxicophobia:BAAALgAECgUJCAAAAA==.',
Tr='Tralle:BAAALgAECgQJCAAAAA==.Treebreak:BAABLgAECn8XAAIgAAgJERBxVABWAQAgAAgJERBxVABWAQAAAA==.Treefity:BAAALgADCgIJAgAAAA==.Trinky:BAAALgAECgMJAwAAAA==.Troublems:BAAALgAECgUJDQAAAA==.',
Ts='Tshi:BAAALgAECgIJAgAAAA==.',
Tu='Turanx:BAAALgAECgIJAgAAAA==.Tutemkhan:BAAALgAECgYJDQAAAA==.',
Tw='Twigrets:BAAALgAECgYJDwAAAA==.',
Ty='Tyrandrea:BAAALgAECgMJAwAAAA==.',
Ug='Ugîn:BAAALgAECgIJAgAAAA==.',
Um='Umbreona:BAAALgAECgMJAwAAAA==.Umàdbrah:BAABLgAECn8bAAIJAAcJXReiGQDHAQAJAAcJXReiGQDHAQAAAA==.',
Un='Unbelievable:BAAALgAECgYJDwAAAA==.Unclechuck:BAAALgADCgQJBwAAAA==.Unholylaezel:BAAALgAECgMJBgAAAA==.',
Va='Valamor:BAABLgAECn8aAAMYAAcJMRymEADdAQAYAAcJMRymEADdAQAnAAEJagUNLQAdAAAAAA==.Valencia:BAAALgADCgIJAgAAAA==.Valicela:BAAALgAECgEJAgAAAA==.Vandamage:BAAALgADCgMJAwAAAA==.Vani:BAAALgAECgMJAwAAAA==.Varenea:BAAALgAECgQJBwAAAA==.Varia:BAAALgADCgYJBgAAAA==.',
Ve='Veefib:BAAALgAECggJEgAAAA==.Velent:BAAALgADCgEJAQAAAA==.Velhari:BAABLgAECn8ZAAMZAAYJuSGKFADFAQAZAAYJsCGKFADFAQAjAAMJ2yGSEwBdAAABLgAFFAQJCQAGAEUYAA==.Velicerus:BAAALgAECgEJAQAAAA==.Velliri:BAAALgAECgMJAwAAAA==.Velvettwitch:BAAALgAECgYJEAAAAA==.Verahla:BAAALgADCgkJHQAAAA==.Vermis:BAAALgAECgQJBwAAAA==.Verona:BAAALgADCgMJAwAAAA==.Veryaverage:BAABLgAECn8UAAIMAAYJVxuvhQDGAQAMAAYJVxuvhQDGAQAAAA==.Vexation:BAAALgAECgMJBQAAAA==.Vexxd:BAAALgAECgUJDAAAAA==.',
Vi='Vicarious:BAAALgAECgYJCgAAAA==.Vidreaux:BAABLgAECn8hAAIBAAgJ3xYmAQASAgABAAgJ3xYmAQASAgAAAA==.Vipora:BAABLgAECn8pAAMFAAgJCR0TBQBfAgAFAAgJCR0TBQBfAgAmAAQJ7go6KwDDAAAAAA==.Visp:BAAALgAECgEJAQAAAA==.',
Vo='Volaura:BAAALgADCgQJBwAAAA==.Volzara:BAABLgAECn8aAAIRAAgJ9xMKGgAPAgARAAgJ9xMKGgAPAgAAAA==.Voìde:BAAALgAECgMJBAAAAA==.',
Vy='Vynesra:BAAALgADCgEJAgAAAA==.',
We='Wetnurse:BAAALgADCgcJBwAAAA==.',
Wh='Whirz:BAAALgAECgcJDQAAAA==.Whizglizzy:BAAALgADCgQJBAAAAA==.Whosethetank:BAAALgADCgcJEgAAAA==.',
Wm='Wmz:BAAALgAECgQJBwAAAA==.',
Wo='Wolfíe:BAAALgAECgEJAQAAAA==.',
Ww='Wwalle:BAAALgAECgUJBwABLgAECgcJGAAgAMgWAA==.',
Xe='Xenarra:BAAALgADCgUJBQAAAA==.',
Xz='Xzavier:BAAALgAECgIJAgAAAA==.',
Ya='Yandros:BAAALgADCgIJAgAAAA==.Yansaa:BAAALgAECgYJEwAAAA==.Yasutora:BAAALgADCgYJCgABLgAECggJGQAWAD0fAA==.',
Yf='Yfelshammy:BAABLgAECn8jAAIKAAgJaw0EJQBCAQAKAAgJaw0EJQBCAQAAAA==.',
Yo='Yogiebear:BAAALgADCgUJBQAAAA==.Yogsøthoth:BAAALgADCgYJBgAAAA==.',
Yr='Yrsea:BAAALgADCgIJAgAAAA==.',
Yu='Yubel:BAAALgAECgQJBAAAAA==.',
Za='Zaevenia:BAAALgADCggJBwAAAA==.Zakka:BAAALgADCgQJBgAAAA==.Zanebusby:BAAALgAECgYJEwAAAA==.Zannahh:BAAALgAECgYJDgAAAA==.Zaraa:BAABLgAECn8UAAINAAYJriEECgAzAgANAAYJriEECgAzAgAAAA==.Zaraë:BAAALgAECgQJBAAAAA==.Zatharis:BAAALgAECgYJCgAAAA==.',
Ze='Zepp:BAAALgAECgEJAgAAAA==.Zerax:BAAALgAECgQJBAAAAA==.Zeroshaman:BAAALgADCgkJDgAAAA==.',
Zi='Ziljin:BAAALgADCgkJCQAAAA==.',
Zz='Zzella:BAABLgAECn8rAAMYAAkJLiNqAACBAwAYAAkJLiNqAACBAwADAAMJowTOEgFxAAAAAA==.',
['Ða']='Ðabzilla:BAABLgAECn8dAAMYAAgJmBsbCQBGAgAYAAgJmBsbCQBGAgADAAIJew8TogBlAAAAAA==.',
['Ðr']='Ðracotalon:BAAALgAECgYJCgAAAA==.Ðragonbeast:BAAALgADCgkJCQAAAA==.',
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
