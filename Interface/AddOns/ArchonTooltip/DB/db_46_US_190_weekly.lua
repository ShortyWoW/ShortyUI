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

local lookup = {'Mage-Arcane','Unknown-Unknown','Priest-Discipline','Evoker-Augmentation','Rogue-Subtlety','Paladin-Retribution','Rogue-Assassination','DeathKnight-Unholy','Shaman-Restoration','Mage-Frost','Shaman-Enhancement','Hunter-Marksmanship','Hunter-BeastMastery','Warlock-Demonology','Warlock-Affliction','Priest-Shadow','Warrior-Arms','Warrior-Fury','Monk-Windwalker','DemonHunter-Havoc','Paladin-Holy','Druid-Guardian','Druid-Feral','Warlock-Destruction','Hunter-Survival','Druid-Balance','Warrior-Protection','Druid-Restoration','DeathKnight-Blood','Shaman-Elemental','DemonHunter-Devourer','DemonHunter-Vengeance','Priest-Holy','Evoker-Devastation','Evoker-Preservation','Paladin-Protection','Monk-Mistweaver','Monk-Brewmaster',}
local provider = {region='US',realm='Shadowsong',name='US',type='weekly',zone=46,date='2026-04-24',data={Ad='Adoran:BAAALgADCgEJAQAAAA==.Adorian:BAAALgAECgEJAQAAAA==.Adrenaleen:BAAALgADCgYJCQAAAA==.',
Ae='Aeosi:BAAALgADCgEJAQAAAA==.Aertin:BAAALgADCgQJBAABLgAECggJIAABAOQYAA==.Aeryhn:BAAALgADCgcJDAABLgADCgkJHwACAAAAAA==.Aezili:BAAALgAECgIJAwAAAA==.',
Af='Afkatie:BAAALgADCggJFAAAAA==.',
Ag='Agaruu:BAAALgAECgYJBgAAAA==.Agerol:BAAALgAECgQJDAAAAA==.Agnin:BAAALgADCgYJCAAAAA==.',
Ak='Akafabu:BAAALgAECgMJBAABLgAFFAIJBQADAMANAA==.Akuryujin:BAABLgAECn8WAAIEAAcJ5A7/CgA2AQAEAAcJ5A7/CgA2AQAAAA==.Akätsuki:BAABLgAECn8SAAIFAAcJMRCxJADTAQAFAAcJMRCxJADTAQAAAA==.',
Al='Alacardias:BAABLgAECn8ZAAIGAAgJ3hzeBABOAgAGAAgJ3hzeBABOAgAAAA==.Aladistra:BAAALgADCgMJAwAAAA==.Albert:BAAALgADCgIJAgAAAA==.Alcaedra:BAAALgADCggJCAAAAA==.Alcapwnz:BAAALgADCgYJCQAAAA==.Alinoda:BAAALgADCgIJAgAAAA==.Alleril:BAABLgAECn8gAAMHAAgJRA7cBwDeAQAHAAgJRA7cBwDeAQAFAAgJIQaiLwCHAQAAAA==.Alley:BAAALgADCgUJCgAAAA==.',
Am='Amäri:BAACLgAFFH8FAAIDAAIJwA2gEwCYAAADAAIJwA2gEwCYAAAuAAQKfyEAAgMACAnHFSMSACQCAAMACAnHFSMSACQCAAAA.',
An='Anassand:BAABLgAECn8XAAIIAAgJXSL/JgCgAgAIAAgJXSL/JgCgAgAAAA==.Andimorph:BAAALgAECgEJAQAAAA==.Anema:BAAALgADCgQJBAABLgAECgMJBQACAAAAAA==.Angeleria:BAAALgAECgYJCgAAAA==.Antebellum:BAAALgAECgcJBQAAAA==.',
Aq='Aqiqi:BAAALgAECgMJBAABLgAECgMJBgACAAAAAA==.Aquashade:BAAALgADCgkJIAABLgAECggJIQAJAPAiAA==.Aquaterra:BAABLgAECn8hAAIJAAgJ8CKuAAD3AgAJAAgJ8CKuAAD3AgAAAA==.',
Ar='Arakadia:BAABLgAECn8bAAIIAAYJBg0GIgAVAQAIAAYJBg0GIgAVAQAAAA==.Aravena:BAAALgADCgMJAwAAAA==.Archetyepe:BAAALgAECgEJAgAAAA==.Aruteeru:BAAALgAECgUJCAAAAA==.',
As='Asathen:BAAALgADCgEJAQAAAA==.Aseanna:BAAALgADCgkJGgAAAA==.Ashadala:BAAALgAECgYJBwAAAA==.Astallivan:BAAALgADCgkJFQAAAA==.',
Au='Augabeks:BAABLgAECn8XAAIEAAgJoBOaGQAAAgAEAAgJoBOaGQAAAgABLgADCgcJBwACAAAAAA==.Auralada:BAABLgAECn8gAAMBAAgJ5Bh+BAACAgABAAcJcht+BAACAgAKAAgJURHOGACAAQAAAA==.Auxhunt:BAAALgADCgkJDQAAAA==.Auxiliator:BAAALgADCgYJCgABLgADCggJCgACAAAAAA==.',
Ay='Ayala:BAABLgAFFH8NAAIGAAQJGCGoAQCEAQAGAAQJGCGoAQCEAQAAAA==.Ayessa:BAAALgAECgQJBgAAAA==.',
Az='Azaireos:BAAALgADCgYJDQAAAA==.Azulpunkt:BAABLgAECn8WAAILAAcJcBQIDwDKAQALAAcJcBQIDwDKAQAAAA==.Azzapp:BAAALgAECgQJBwAAAA==.',
Ba='Baddaboomkin:BAAALgAECgEJAQAAAA==.Bakreingol:BAAALgADCgUJBQABLgAECgEJAQACAAAAAA==.Barbedwire:BAAALgAECgcJBAAAAA==.Baree:BAAALgADCgIJAQAAAA==.',
Be='Bearmao:BAABLgAECn8dAAMMAAgJgg7EQQBQAQAMAAcJaQzEQQBQAQANAAQJKQ78IQDzAAAAAA==.Bearserk:BAAALgAECgIJBAAAAA==.Beastknight:BAAALgAECgIJAgAAAA==.Beastrunner:BAAALgADCgYJCAABLgAECgIJAgACAAAAAA==.Beknight:BAAALgAFFAEJAQABLgADCgcJBwACAAAAAA==.Belfas:BAAALgAECgQJBQAAAA==.Bellybutton:BAAALgAECgMJBAAAAA==.Benafflok:BAACLgAFFH8FAAMOAAQJbA35OQCfAAAOAAMJJA75OQCfAAAPAAEJRAt2BgBRAAAuAAQKfyAAAw8ACAmdI3YDAGMCAA4ACAk5Ig4fAJ0CAA8ABwn9H3YDAGMCAAAA.Bertu:BAAALgADCgEJAQAAAA==.',
Bi='Bigblight:BAAALgADCgEJAQAAAA==.Bigduck:BAAALgAECgUJCgAAAA==.Biggayjohn:BAAALgAECgEJAgAAAA==.Bigknighter:BAAALgAECgYJDgAAAA==.',
Bl='Blackclover:BAABLgAECn8aAAIJAAgJjRxPIwALAgAJAAgJjRxPIwALAgAAAA==.Blackpink:BAAALgADCgYJBwAAAA==.Blandicus:BAAALgADCgcJBwAAAA==.',
Bo='Boppaheks:BAAALgADCgcJBwAAAA==.Bowless:BAAALgAECgEJAQAAAA==.',
Br='Brawnstone:BAAALgAECgEJAQAAAA==.Brewsleroy:BAAALgADCgcJDQAAAA==.Brewtypoppin:BAAALgADCgQJBAAAAA==.Brey:BAAALgADCgMJAwAAAA==.Brohomir:BAAALgADCggJCQAAAA==.Bronze:BAAALgAECgQJBAAAAA==.Brunee:BAABLgAECn8WAAIQAAgJzwpEJwCeAQAQAAgJzwpEJwCeAQAAAA==.Bruute:BAABLgAECn8aAAIRAAcJ5R6zAQDsAQARAAcJ5R6zAQDsAQAAAA==.',
Bu='Budplatinum:BAAALgAECgMJAwAAAA==.Buffbuffheal:BAAALgAECgMJAwABLgAECgYJCgACAAAAAA==.Buhemoth:BAAALgAECgcJDgAAAA==.Bumi:BAAALgADCgQJBAAAAA==.',
Ca='Caemaris:BAAALgADCgQJBAAAAA==.Cairo:BAABLgAECn8XAAISAAgJrhhGIwA7AgASAAgJrhhGIwA7AgAAAA==.Cakes:BAAALgAECgUJDgAAAA==.Calai:BAAALgADCgYJCgAAAA==.Canadiian:BAAALgAECgYJDwAAAA==.Capitalchaos:BAABLgAECn8ZAAISAAgJvhOkBgC6AQASAAgJvhOkBgC6AQAAAA==.Cassandraa:BAAALgAECgEJAQAAAA==.',
Ce='Cearreotadh:BAAALgADCgQJBAAAAA==.Ceviche:BAABLgAECn8YAAITAAgJMyO5BQAoAwATAAgJMyO5BQAoAwAAAA==.Ceàrrdòrn:BAABLgAECn8VAAIGAAYJkCECEQCcAQAGAAYJkCECEQCcAQAAAA==.',
Ch='Cheetahgirl:BAAALgAECgEJAQAAAA==.Chickenjoy:BAAALgADCgcJBwAAAA==.Chillzmatic:BAABLgAECn8VAAIUAAYJ9iCWGAACAgAUAAYJ9iCWGAACAgAAAA==.Chirri:BAAALgADCggJFgAAAA==.Chondriac:BAAALgAECgcJEAAAAA==.Chow:BAAALgADCgQJBAAAAA==.Chrisdirect:BAAALgADCgQJBAAAAA==.Chudbucket:BAAALgAECgUJDgAAAA==.',
Ci='Cinabun:BAAALgADCgIJAgAAAA==.Cirillø:BAAALgAECgkJDAAAAA==.',
Cl='Cloverblack:BAAALgADCgEJAQAAAA==.',
Co='Corbis:BAAALgAECgUJCwAAAA==.Covidmage:BAAALgADCgUJBQAAAA==.Cowpatty:BAAALgADCgYJCgAAAA==.',
Cu='Cuchi:BAAALgADCgkJDAAAAA==.Cutename:BAAALgADCgYJBQAAAA==.',
Cy='Cyraea:BAAALgAECgIJBAAAAA==.',
Cz='Czeskilight:BAAALgAECgYJEwAAAA==.',
['Câ']='Câl:BAAALgADCgUJBQAAAA==.',
['Cå']='Cåle:BAAALgAECgQJBQAAAA==.',
Da='Daane:BAAALgADCgYJCgAAAA==.Dabadwarrior:BAABLgAECn8gAAISAAgJFhB6CACYAQASAAgJFhB6CACYAQAAAA==.Dabs:BAAALgAECgEJAQAAAA==.Dabzîlla:BAAALgADCggJCAABLgAECggJGQAVAE4XAA==.Daffadill:BAAALgADCgEJAQAAAA==.Dakhran:BAAALgADCgUJFAAAAA==.Danero:BAAALgAECgEJAQAAAA==.Darkchangu:BAAALgAECgMJAwAAAA==.Darkdemon:BAAALgAECgYJEwAAAA==.Darkovia:BAAALgADCgMJAwAAAA==.',
De='Deagle:BAACLgAFFH8HAAIFAAMJORk1BQAVAQAFAAMJORk1BQAVAQAuAAQKfygAAgUACAloI5EAAL4CAAUACAloI5EAAL4CAAAA.Deedubbya:BAAALgADCgMJAwAAAA==.Defense:BAAALgADCgkJDQAAAA==.Demonfrog:BAABLgAECn8bAAIIAAgJXRCUFwBVAQAIAAgJXRCUFwBVAQAAAA==.Desideria:BAAALgAECgQJCwAAAA==.Desynn:BAABLgAECn8YAAIOAAcJdBPdEgB5AQAOAAcJdBPdEgB5AQAAAA==.Deyndel:BAABLgAECn8UAAIGAAYJ6AXjvwAHAQAGAAYJ6AXjvwAHAQAAAA==.',
Di='Divinesyn:BAAALgAECgMJAwAAAA==.',
Dj='Djtaki:BAABLgAECn8ZAAMFAAcJFxfGBAC2AQAFAAcJFxfGBAC2AQAHAAEJXA+MHQA/AAAAAA==.',
Do='Dobs:BAABLgAECn8XAAIWAAgJ/xg9CAAqAgAWAAgJ/xg9CAAqAgAAAA==.Dogwater:BAAALgAECggJEwABLgAFFAQJBgAXAPobAA==.Domimpatrix:BAAALgADCgYJBgAAAA==.Doncarlos:BAAALgAECgQJBAAAAA==.Dotsonly:BAAALgAECgYJCQAAAA==.Dotty:BAAALgAECgIJBAAAAA==.Downbeatxo:BAECLgAFFH8SAAMOAAYJHByUAADiAQAOAAYJHByUAADiAQAYAAEJSBXKFABVAAAuAAQKfyUAAw4ACQknJDgLACEDAA4ACAknJDgLACEDABgAAgnUHCZOAIMAAAAA.',
Dr='Dracow:BAAALgADCgkJEgABLgAECgcJEgACAAAAAA==.Dragonflash:BAAALgAECgcJDQAAAA==.',
Du='Dubdred:BAAALgAECgEJAQABLgAECgYJFAAVAMgTAA==.Duberrok:BAABLgAECn8UAAMVAAYJyBOdDgBUAQAVAAYJyBOdDgBUAQAGAAMJxQ09+wCdAAAAAA==.Dunes:BAAALgAECgQJBAAAAA==.Dunidane:BAAALgADCgYJBgAAAA==.Durk:BAAALgAECgUJCQAAAA==.',
Dw='Dwarfskin:BAAALgADCgQJBQAAAA==.Dwín:BAABLgAECn8WAAMNAAgJvQVkGAA4AQANAAgJvQVkGAA4AQAMAAEJ+QB4mgAYAAAAAA==.',
Ea='Earthstalker:BAAALgADCgkJFQAAAA==.',
Ek='Ekzykes:BAAALgAECgIJAgAAAA==.',
El='Elasper:BAAALgAECgIJAwAAAA==.Eleathis:BAAALgADCggJHQAAAA==.',
Em='Emäcs:BAAALgADCgIJAgAAAA==.',
En='Enjin:BAABLgAECn8VAAIZAAcJyx+oBgCSAgAZAAcJyx+oBgCSAgAAAA==.Enragedbeef:BAAALgAECgYJEwABLgAECggJFQAOACoTAA==.Entheogen:BAAALgAECgUJCAAAAA==.',
Er='Erahlon:BAAALgADCgkJHQAAAA==.Eralak:BAAALgADCgIJAgAAAA==.Ereckshaun:BAAALgADCgEJAQAAAA==.Eree:BAAALgAECgMJAwAAAA==.Erinora:BAAALgAECgEJAQABLgAFFAIJBAACAAAAAA==.Ermoonsia:BAAALgADCgcJDAAAAA==.Erolas:BAAALgAECgEJAQAAAA==.',
Ev='Evanessance:BAAALgADCggJEgAAAA==.Evoka:BAAALgAECgYJEAAAAA==.',
Fa='Faavimonk:BAAALgAECgkJDAAAAA==.Fallendevout:BAAALgADCgkJEQAAAA==.Fallendots:BAAALgADCgUJCQAAAA==.Fallenseer:BAAALgAECgYJEwAAAA==.Fallentroll:BAAALgAECggJDQAAAA==.Fatman:BAAALgAECgUJCgAAAA==.Faydark:BAAALgAECgQJBAAAAA==.Fayia:BAAALgADCgkJFwAAAA==.Fayye:BAAALgAECgMJAwAAAA==.',
Fe='Feliandril:BAAALgAECgEJAQAAAA==.Fellin:BAABLgAECn8YAAIMAAYJJwbFBwDsAAAMAAYJJwbFBwDsAAAAAA==.Femto:BAACLgAFFH8IAAIIAAMJ2SHYIAAVAQAIAAMJ2SHYIAAVAQAuAAQKfysAAggACAlRIkEaAN8CAAgACAlRIkEaAN8CAAAA.',
Fi='Fiestyrae:BAAALgADCgYJAwAAAA==.Fiorina:BAAALgAECgEJAQABLgAECgYJFAAaANUVAA==.Fireburd:BAAALgADCgQJBAAAAA==.Firèflyjd:BAAALgAECgQJBAAAAA==.Fishersam:BAAALgADCgYJBgAAAA==.Fishy:BAAALgADCgkJDwAAAA==.',
Fl='Flintzombie:BAAALgADCgkJCQABLgAECggJGAAbAHEQAA==.Floatpass:BAABLgAECn8UAAIKAAgJ+hZ8fADYAQAKAAgJ+hZ8fADYAQAAAA==.Floweranjel:BAAALgADCgYJCgAAAA==.Fluffymyone:BAAALgAECgcJEwAAAA==.',
Fo='Foghat:BAAALgADCgcJCgAAAA==.Fongsiyuk:BAAALgAECgYJEQAAAA==.Foxhammer:BAAALgADCgcJBwAAAA==.',
Fr='Freezeberry:BAAALgAECgEJAQAAAA==.Frizz:BAAALgADCggJBgAAAA==.Froey:BAAALgADCgQJBAAAAA==.Froeyglaive:BAAALgAECgQJCAAAAA==.',
Fu='Furlog:BAAALgADCgYJBwAAAA==.Fuzz:BAAALgADCgIJAgAAAA==.Fuzzymonk:BAAALgAECgcJDAAAAA==.Fuzzytotems:BAABLgAFFH8GAAIJAAMJRhh9BgDxAAAJAAMJRhh9BgDxAAAAAA==.',
['Fá']='Fáavi:BAAALgADCgQJBAABLgAECgkJDAACAAAAAA==.',
Ga='Gabagooly:BAAALgAECgIJAgAAAA==.Gali:BAACLgAFFH8JAAMNAAMJNg/oDQDoAAANAAMJNg/oDQDoAAAMAAEJ6wFICgA9AAAuAAQKfyYAAw0ACAkXG3UOAMgCAA0ACAnVGnUOAMgCAAwABwkwFGk6AHYBAAAA.Galiagante:BAAALgADCgcJCwAAAA==.Galiashammy:BAAALgADCgUJBQABLgADCgcJCwACAAAAAA==.Gallynna:BAABLgAECn8YAAQOAAYJpRDfHwAiAQAOAAUJQQ3fHwAiAQAYAAUJbRCqNADkAAAPAAEJAACTMwA2AAAAAA==.Galorfax:BAAALgAECgQJDAAAAA==.Galorfox:BAAALgADCgUJBQAAAA==.Galushi:BAAALgAECgEJAQAAAA==.Gamervato:BAAALgAECgIJAgAAAA==.Gannondalf:BAAALgADCgUJBQABLgAECggJGAAbAHEQAA==.Garlic:BAAALgAECgMJBQAAAA==.Garm:BAAALgAECgcJEQAAAA==.',
Ge='Gelinea:BAAALgAECgQJCgAAAA==.Genovese:BAAALgAECgcJBwAAAA==.Gerardbutler:BAAALgADCgkJCQAAAA==.Geyboy:BAAALgAECgEJAQAAAA==.',
Gi='Gilgameshx:BAAALgADCgIJAgAAAA==.Gilgaroth:BAABLgAECn8YAAIFAAcJOBhDIgDnAQAFAAcJOBhDIgDnAQAAAA==.Girdlin:BAAALgADCgcJEgAAAA==.',
Gl='Glaucoma:BAAALgADCgkJGQAAAA==.',
Go='Gobo:BAAALgAECgMJAwABLgAECgYJDwACAAAAAA==.Gorendish:BAAALgADCggJCAAAAA==.',
Gr='Graevus:BAABLgAECn8eAAIcAAgJXRclIQA7AgAcAAgJXRclIQA7AgAAAA==.Graku:BAAALgAECgkJBwAAAA==.Graysonn:BAAALgADCgkJEAAAAA==.Greyheart:BAAALgADCgUJBQAAAA==.Grimmora:BAAALgADCgQJBAAAAA==.Grëybeard:BAAALgAECgYJEAABLgAECggJJgAdABEfAA==.',
Gu='Gundrakk:BAABLgAECn8cAAIcAAgJ6xvfFwB3AgAcAAgJ6xvfFwB3AgAAAA==.Gunnr:BAAALgAECgQJBAABLgAECgQJBgACAAAAAA==.Gunthorian:BAABLgAECn8UAAMVAAYJWg/dTABFAQAVAAYJWg/dTABFAQAGAAYJPA6ypgA0AQAAAA==.',
Ha='Hame:BAAALgADCgMJAwAAAA==.Hamme:BAAALgADCgEJAQAAAA==.Handsomemonk:BAAALgAECgUJEgAAAA==.Hangvhul:BAABLgAECn8YAAILAAgJ0w7ZDQDfAQALAAgJ0w7ZDQDfAQAAAA==.Hansi:BAAALgAECgQJBQAAAA==.Harkonnen:BAABLgAECn8aAAMOAAgJHQpIHAA3AQAOAAgJGQlIHAA3AQAYAAEJ+ROpcQA0AAAAAA==.',
He='Healmme:BAAALgAECgUJBQAAAA==.Heart:BAAALgAECgMJBgAAAA==.Hectic:BAAALgADCgEJAQABLgAECggJGQAVAE4XAA==.Heid:BAAALgAECgEJAQAAAA==.Helianna:BAAALgAECgQJBgABLgAFFAQJCgANAGgQAA==.Helldozer:BAAALgAECgIJAwAAAA==.',
Hi='Himejoshi:BAACLgAFFH8GAAIXAAQJ+hsMAQAfAQAXAAQJ+hsMAQAfAQAuAAQKfx4AAxcACAmOJGcBAFwDABcACAmOJGcBAFwDABYABwkVHuAFAHUCAAAA.Hirys:BAAALgAFFAEJAQAAAA==.',
Ho='Holybanana:BAAALgAECgYJDQAAAA==.Holymerble:BAAALgAECgEJAQABLgAECgcJCgACAAAAAA==.Holyramen:BAAALgADCgcJBwAAAA==.Horsewing:BAAALgAECgYJEAAAAA==.Hotmerble:BAAALgAECgcJCgAAAA==.Hotshotzz:BAAALgAECgQJBgABLgAFFAEJAQACAAAAAA==.Hotstreak:BAAALgAFFAEJAQABLgAFFAEJAQACAAAAAA==.',
Hu='Huntsmedown:BAAALgADCgkJEwAAAA==.',
Hy='Hyjali:BAAALgADCgEJAQAAAA==.',
['Há']='Háldrin:BAABLgAFFH8KAAMNAAQJaBDKBAAyAQANAAQJUQ7KBAAyAQAMAAIJDA1CIACUAAAAAA==.',
['Hä']='Härmacist:BAAALgAECgUJBQAAAA==.',
Il='Illexi:BAAALgADCgYJBgAAAA==.Ilthunis:BAAALgADCgcJEAAAAA==.',
Im='Imadruîd:BAAALgAECgQJBAAAAA==.Imbue:BAAALgAECgYJEAAAAA==.Immortals:BAAALgAECgQJBQAAAA==.',
In='Innil:BAAALgAECgcJCgAAAA==.',
Ip='Ipunch:BAAALgAECgQJBwAAAA==.',
Ja='Jaesa:BAAALgADCgEJAQAAAA==.',
Je='Jessiks:BAAALgADCgEJAQAAAA==.Jetlisa:BAAALgADCgcJBwAAAA==.Jezebel:BAABLgAECn8XAAMOAAcJgghcJgD7AAAOAAYJSglcJgD7AAAYAAEJlgSQEgAkAAAAAA==.',
Ji='Jiaoe:BAAALgADCgQJBAAAAA==.Jinxing:BAAALgAECgMJAwAAAA==.Jinze:BAAALgAECgEJAQAAAA==.Jirito:BAAALgADCgcJBwABLgAECggJEwACAAAAAA==.Jirto:BAAALgAECggJEwAAAA==.',
Jo='Jomadead:BAAALgAECgYJEQABLgAFFAUJDgAJALoNAA==.Jomadin:BAAALgAECgEJAQABLgAFFAUJDgAJALoNAA==.Jomage:BAAALgADCgcJBwABLgAFFAUJDgAJALoNAA==.Jomar:BAAALgAECgEJAQAAAA==.Jomas:BAACLgAFFH8OAAIJAAUJug2lAgBhAQAJAAUJug2lAgBhAQAuAAQKfygAAwkACQkPH+UHAPYCAAkACQkPH+UHAPYCAB4ABQkLILwxAJUBAAAA.',
Ju='Jubbjubb:BAACLgAFFH8FAAIKAAMJSwkLFADzAAAKAAMJSwkLFADzAAAuAAQKfyUAAgoACAkQH4Y0AKECAAoACAkQH4Y0AKECAAAA.Judera:BAAALgAECgcJEgAAAA==.Jugful:BAAALgAECgEJAQAAAA==.Juicemoose:BAAALgAECgYJDAAAAA==.Juicybooty:BAAALgADCgUJBQAAAA==.Justokelf:BAABLgAECn8XAAIfAAcJxB7lDQCfAQAfAAcJxB7lDQCfAQAAAA==.',
Jw='Jwarr:BAAALgADCgEJAQAAAA==.',
Ka='Kagura:BAAALgADCgcJBwAAAA==.Kaiden:BAAALgADCgcJEgAAAA==.Kaing:BAAALgAECgQJCQAAAA==.Kainlithia:BAAALgAECgYJCAAAAA==.Kaladen:BAAALgAECgEJAgAAAA==.Kalindica:BAAALgADCgYJBgAAAA==.Kalysti:BAAALgAECgYJFAAAAQ==.Kandee:BAAALgAECgYJEQAAAA==.Karkonas:BAAALgADCgEJAQABLgAECgcJDwACAAAAAA==.Karliahdark:BAAALgADCgcJDQAAAA==.Karolg:BAAALgAECgQJBAAAAA==.Karuli:BAAALgADCgkJIgAAAA==.Karvis:BAAALgAECgUJDgAAAA==.Kasuri:BAAALgAECgEJAQAAAA==.Katostrafic:BAAALgAECgYJCgAAAA==.Kazemage:BAAALgAECggJDwAAAA==.',
Ke='Kevais:BAAALgADCgQJBwAAAA==.',
Kh='Khromscarin:BAABLgAECn8gAAIgAAgJOB4cAwCvAgAgAAgJOB4cAwCvAgAAAA==.',
Ki='Kielli:BAAALgADCgEJAQAAAA==.Killboi:BAAALgAECgMJAwAAAA==.Killidan:BAACLgAFFH8GAAIfAAMJvRb1DAD2AAAfAAMJvRb1DAD2AAAuAAQKfxkAAh8ACAnqI30RAPICAB8ACAnqI30RAPICAAAA.Kimberllynn:BAAALgAECgcJBwAAAA==.Kiridus:BAABLgAECn8UAAMaAAYJ1RXbCQBQAQAaAAYJ1RXbCQBQAQAcAAEJoQTu4QAjAAAAAA==.Kirklees:BAAALgADCgUJCQAAAA==.',
Kl='Klaudiuss:BAAALgADCgEJAQAAAA==.',
Kn='Knackers:BAAALgADCggJDQAAAA==.',
Ko='Kodama:BAABLgAECn8dAAIeAAcJahLXCQBeAQAeAAcJahLXCQBeAQAAAA==.Koi:BAAALgADCgkJCQABLgAECgYJFwAfAKsjAA==.Kookiesplz:BAAALgADCgkJDAAAAA==.Kopili:BAAALgAECgQJBwAAAA==.Koryn:BAABLgAECn8VAAIQAAYJxA0JEAD2AAAQAAYJxA0JEAD2AAAAAA==.Kotz:BAAALgAECgYJDAAAAA==.',
Kr='Kratina:BAAALgADCgEJAQAAAA==.Krunthe:BAAALgAECgQJBAAAAA==.Kryxis:BAAALgAECgUJBgAAAA==.',
Ku='Kunpochiken:BAAALgAECgQJBAABLgAECgYJCgACAAAAAA==.',
La='Lacrymos:BAABLgAECn8dAAIgAAgJIhe1AQDIAQAgAAgJIhe1AQDIAQAAAA==.Larril:BAAALgADCgYJBwAAAA==.Laurebeth:BAAALgADCgkJDQAAAA==.Laxinmedium:BAAALgAECgEJAQAAAA==.',
Le='Lesavatar:BAAALgADCgUJBQAAAA==.Levande:BAABLgAECn8WAAMhAAgJBxnpEgBIAgAhAAgJqhjpEgBIAgADAAUJ/Q2TMQAUAQAAAA==.',
Li='Lid:BAAALgADCgMJAwAAAA==.Lighttickle:BAAALgADCgMJAwAAAA==.Liling:BAAALgADCgEJAgABLgAECgYJCgACAAAAAA==.Lilithandria:BAAALgAECgcJEgAAAA==.Lilletth:BAAALgADCgUJBQAAAA==.Lilyola:BAAALgAECgUJBgAAAA==.Linamar:BAAALgADCgkJHwAAAA==.',
Lo='Loaq:BAABLgAECn8XAAIDAAgJcB3OCACvAgADAAgJcB3OCACvAgAAAA==.Lockzrockz:BAAALgADCgcJBwAAAA==.Lorbert:BAAALgADCgUJBwABLgAECgcJGQASAPMWAA==.',
Lu='Luxæterna:BAABLgAECn8cAAIGAAgJtBozJgCNAgAGAAgJtBozJgCNAgAAAA==.',
Ly='Lystrasza:BAAALgAECgUJCwAAAA==.Lyte:BAAALgADCgYJCgAAAA==.',
['Lí']='Líllìth:BAAALgADCgYJBgAAAA==.',
Ma='Madjekyll:BAAALgADCgYJCQABLgAECgQJDAACAAAAAA==.Maikeru:BAAALgAECgUJDgAAAA==.Malduku:BAAALgADCgYJBgAAAA==.Malemenas:BAAALgADCgkJIQAAAA==.Malice:BAABLgAECn8fAAIPAAgJsx5lAQDfAgAPAAgJsx5lAQDfAgAAAA==.Mandwandos:BAAALgAECgcJCQAAAA==.Maraliss:BAAALgAECgQJBAAAAA==.Marjon:BAAALgAECgUJCQAAAA==.Maroonfive:BAAALgAECgEJAgAAAA==.Marrash:BAAALgADCgcJBgAAAA==.Masashii:BAAALgADCgQJBAABLgAECgYJFwAfAKsjAA==.Mastatea:BAAALgADCggJCgAAAA==.Matamoros:BAAALgADCgcJCAAAAA==.Maugrimm:BAAALgADCggJCwAAAA==.Maxn:BAAALgADCgcJBwAAAA==.Maxrox:BAAALgAECgQJBAAAAA==.Mayalodu:BAAALgAECgQJEQAAAA==.',
Me='Melaunis:BAAALgAECgEJAQAAAA==.Mellwynn:BAAALgADCgMJAwAAAA==.Mellínna:BAAALgADCgYJCwAAAA==.Meora:BAAALgAECgIJAgABLgAFFAMJCQAbAL8SAA==.Meowow:BAAALgAECgYJCwAAAA==.Merks:BAAALgAECgMJBAAAAA==.Metas:BAAALgAECgYJBgABLgAFFAMJCQAbAL8SAA==.Meteora:BAACLgAFFH8JAAIbAAMJvxK2AwDgAAAbAAMJvxK2AwDgAAAuAAQKfyEAAhsACAk5HZkIAJYCABsACAk5HZkIAJYCAAAA.',
Mh='Mhithrha:BAAALgAECgYJDQAAAA==.',
Mi='Migolbearcow:BAABLgAECn8aAAIWAAgJ8Q+oBAAsAQAWAAgJ8Q+oBAAsAQAAAA==.Miinx:BAAALgAECgcJBwAAAA==.Minervamon:BAAALgADCgMJAwAAAA==.Missed:BAABLgAECn8cAAIGAAgJFiPXAQC0AgAGAAgJFiPXAQC0AgAAAA==.Missedweaver:BAAALgAECgUJBgABLgAECggJHAAGABYjAA==.Miyuni:BAAALgADCgMJAwAAAA==.',
Ml='Mlglock:BAABLgAECn8XAAIOAAkJ6hs9IgCMAgAOAAkJ6hs9IgCMAgAAAA==.',
Mo='Mongocrush:BAAALgADCggJFQAAAA==.Moocifur:BAAALgADCgkJCQAAAA==.Moonbeary:BAAALgAECgcJBwAAAA==.Mooniè:BAAALgAECgQJBAAAAA==.Moosenuts:BAAALgADCgMJAwAAAA==.Moxxii:BAABLgAECn8WAAMdAAgJlhz2DwANAgAdAAYJmiD2DwANAgAIAAMJjg8u5wCxAAAAAA==.',
Mu='Muradigme:BAAALgAECgMJAwAAAA==.Mushufasa:BAAALgADCgQJBAAAAA==.Mutilusgore:BAABLgAECn8YAAIbAAgJcRCKBQBZAQAbAAgJcRCKBQBZAQAAAA==.',
My='Myrium:BAAALgADCggJFAAAAA==.Myshella:BAAALgAECgYJCgAAAA==.Myylus:BAAALgADCgcJCAAAAA==.',
['Mö']='Mökes:BAABLgAECn8VAAIYAAgJcyFVAQAZAwAYAAgJcyFVAQAZAwAAAA==.',
Na='Naijin:BAAALgADCgEJAQABLgAECgYJCgACAAAAAA==.Nasana:BAAALgADCgQJBAAAAA==.Navarra:BAAALgADCgEJAQAAAA==.Nawzero:BAAALgADCgQJBAAAAA==.Nax:BAAALgAECgEJBAAAAA==.Nazeiro:BAABLgAECn8UAAIfAAgJjg3NeAA8AQAfAAgJjg3NeAA8AQAAAA==.Nazzersaurus:BAAALgAECgYJCgAAAA==.',
Ne='Negies:BAAALgADCgYJBgAAAA==.Nekestinea:BAAALgADCgIJAgAAAA==.Nekomata:BAAALgAECgYJDwAAAA==.Nekosmasta:BAAALgADCggJCAAAAA==.Neodin:BAAALgADCgkJHwAAAA==.Newhamme:BAAALgADCgkJGAAAAA==.',
Ni='Nightjewel:BAAALgAECgEJAQAAAA==.',
No='Noctevera:BAAALgADCgkJCQAAAA==.Noggs:BAAALgAECgEJAQAAAA==.Nokawa:BAAALgADCgYJBgAAAA==.Nokkas:BAAALgAECgEJAQAAAA==.Novadisc:BAAALgADCggJCAAAAA==.',
Nu='Nuali:BAAALgADCgkJEQABLgAECgYJGAAhALUeAA==.Numbers:BAABLgAECn8bAAIVAAkJDBy1CADkAgAVAAkJDBy1CADkAgAAAA==.',
['Nê']='Nêrtt:BAABLgAECn8hAAMiAAgJWR3xBQCYAgAiAAcJkh/xBQCYAgAjAAgJ/RX+AQAQAgAAAA==.',
Oc='Oche:BAAALgADCgYJBwABLgAECgYJCgACAAAAAA==.',
Ok='Oketra:BAAALgADCgUJBQAAAA==.',
Om='Omniia:BAAALgAECgMJAwAAAA==.',
On='Onedog:BAAALgADCgEJAQAAAA==.Ontera:BAAALgAECgYJCgAAAA==.',
Or='Orala:BAABLgAECn8YAAIQAAYJuxbPCQBTAQAQAAYJuxbPCQBTAQAAAA==.Orý:BAABLgAECn8nAAIeAAkJgBtJAgBBAgAeAAkJgBtJAgBBAgAAAA==.',
Os='Oslatem:BAAALgAECgIJAwAAAA==.',
Ot='Ottrekker:BAAALgADCgIJAgABLgAECgYJDAACAAAAAA==.',
Ov='Overlie:BAAALgADCgIJAgAAAA==.',
Ox='Oxosorrel:BAAALgAECgEJAQAAAA==.',
Pa='Paladan:BAACLgAFFH8GAAMGAAMJeBrwBwAQAQAGAAMJeBrwBwAQAQAkAAEJ+xNwBwA9AAAuAAQKfxgAAwYACAloJWMLADMDAAYACAkkJWMLADMDACQABgmMI98IAEgCAAAA.Paladeez:BAAALgAECgQJBAAAAA==.Palyboye:BAAALgADCgQJBAAAAA==.Pandamonea:BAAALgADCggJDgABLgAECgIJAgACAAAAAA==.Pandamonium:BAAALgADCgYJCQABLgAECgIJAgACAAAAAA==.Pandapunkt:BAAALgAECgYJCgAAAA==.Pandragon:BAAALgAECgIJAgAAAA==.Papstlock:BAAALgAECgIJAwAAAA==.Parishealton:BAABLgAECn8eAAIcAAgJUB5XAgCcAgAcAAgJUB5XAgCcAgAAAA==.Pastybeard:BAABLgAECn8XAAIPAAgJPCHXAgCFAgAPAAgJPCHXAgCFAgAAAA==.Pazzuzu:BAAALgADCggJCQAAAA==.',
Pe='Penjamin:BAAALgAECgUJCAAAAA==.Pewnani:BAAALgADCgMJAwAAAA==.',
Pl='Planetes:BAAALgAECgIJBAAAAA==.',
Po='Pontar:BAAALgAECgYJBgAAAA==.Portalnugget:BAAALgAECgEJAQABLgAECggJHAAcAOsbAA==.Portalz:BAAALgADCgYJBwABLgAECggJHAAGABYjAA==.',
Pr='Prominence:BAAALgAECgcJEgAAAA==.Proy:BAAALgAECgEJAgAAAA==.Prozak:BAABLgAECn8WAAIJAAgJnAp9DgBYAQAJAAgJnAp9DgBYAQAAAA==.',
Ps='Psychofrenic:BAAALgADCgMJAwABLgAECggJGQASAL4TAA==.',
Pu='Puhlayden:BAABLgAECn8XAAMGAAgJax7xOAA/AgAGAAcJ0B7xOAA/AgAVAAcJCQqFRQBiAQAAAA==.',
['Pò']='Pòppy:BAAALgADCgcJBwAAAA==.',
Qu='Quikanez:BAAALgAECgYJCgAAAA==.Qulung:BAAALgADCgkJCQAAAA==.',
Ra='Radmane:BAAALgADCgEJAQAAAA==.Raegasm:BAAALgADCgQJBQAAAA==.Raein:BAAALgAECgQJBgAAAA==.Raithe:BAAALgADCgQJBAAAAA==.Raskela:BAABLgAECn8XAAIlAAgJmRwBDgB2AgAlAAgJmRwBDgB2AgAAAA==.Raskella:BAAALgAECgEJAQABLgAECggJFwAlAJkcAA==.Ratboy:BAABLgAECn8YAAMFAAgJ7Bh4DwCtAgAFAAgJ7Bh4DwCtAgAHAAEJ2g7RIAAuAAAAAA==.Ratkiss:BAAALgADCgYJBgAAAA==.',
Re='Reckhn:BAAALgADCgYJBgAAAA==.Reprieve:BAAALgAECgYJEgAAAA==.Reversal:BAAALgAECgQJBAABLgAECggJGQASAL4TAA==.Rexe:BAAALgAFFAIJBAAAAA==.Rexy:BAAALgAECgYJBwABLgAFFAIJBAACAAAAAA==.',
Rh='Rhane:BAAALgAECgQJCAAAAA==.Rhazputin:BAAALgAECgQJBQAAAA==.Rhend:BAAALgADCgcJBwAAAA==.',
Ri='Riang:BAAALgADCgcJBwAAAA==.Rickcando:BAAALgAECgQJCQAAAA==.Ricshard:BAABLgAECn8UAAMYAAYJDhZ2BAAPAQAYAAUJJRZ2BAAPAQAOAAEJshWASgBIAAAAAA==.Ridjeckgron:BAAALgAECgEJAQAAAA==.Righteouskat:BAAALgADCgIJAgAAAA==.Rinea:BAABLgAECn8YAAMhAAYJtR61BQDEAQAhAAYJtR61BQDEAQAQAAEJ6gRZZgAsAAAAAA==.Risse:BAAALgAECgYJCgAAAA==.',
Ro='Roarkitty:BAAALgAECgUJDAAAAA==.Rocknaw:BAAALgAECgcJEwAAAA==.Rodgers:BAAALgAECgYJBgABLgAFFAMJCQAbAL8SAA==.Rogaldorne:BAAALgAECgYJCQAAAA==.Romans:BAAALgADCgcJDwABLgAECgkJGwAVAAwcAA==.Ronicary:BAAALgADCgEJAQAAAA==.Roofeed:BAAALgADCgEJAQAAAA==.Rospeteal:BAABLgAECn8dAAIYAAgJIROFEQDAAQAYAAgJIROFEQDAAQAAAA==.',
Ru='Ruben:BAAALgADCgYJCAAAAA==.Runefnar:BAAALgADCgkJEwAAAA==.Rungar:BAAALgADCgQJBAAAAA==.',
Ry='Rydmytotem:BAAALgADCgcJEwAAAA==.Rylia:BAAALgADCgkJFgAAAA==.Ryuhari:BAABLgAECn8UAAIWAAYJSSIlCAAtAgAWAAYJSSIlCAAtAgAAAA==.Ryujin:BAABLgAECn8WAAMFAAgJUwy6BwBjAQAFAAgJ4wu6BwBjAQAHAAMJZgWDGQBgAAAAAA==.',
['Ró']='Ród:BAAALgAFFAEJAQAAAA==.',
Sa='Saalira:BAAALgAECgEJAQAAAA==.Sabellice:BAABLgAECn8UAAIGAAYJIBTigAB4AQAGAAYJIBTigAB4AQAAAA==.Sadicia:BAAALgADCgEJAQAAAA==.Sakonna:BAAALgAFFAIJBAAAAA==.Saltyfingers:BAAALgADCggJCAAAAA==.Samwell:BAAALgADCgcJCAAAAA==.Saniroin:BAAALgADCgIJAgAAAA==.Sarlius:BAABLgAECn8fAAINAAkJXCTAAAC5AwANAAkJXCTAAAC5AwAAAA==.Savin:BAAALgAECgQJBAAAAA==.',
Sc='Scargrimm:BAAALgAECgcJBgAAAA==.Scavenger:BAAALgADCgUJBQAAAA==.Schorsha:BAAALgAECgQJCQAAAA==.',
Se='Selkamonk:BAABLgAECn8YAAMlAAYJCSQqAgBkAgAlAAYJCSQqAgBkAgATAAEJAACKdQBAAAAAAA==.Sentrina:BAABLgAECn8nAAIjAAkJaBjRDwA9AgAjAAkJaBjRDwA9AgAAAA==.Seramon:BAAALgADCgQJBAABLgAECgcJFQAZAMsfAA==.Seraph:BAAALgAECgEJAgAAAA==.Serennia:BAAALgADCgEJAQAAAA==.Seshy:BAAALgAECgQJDAABLgAECggJFQAOACoTAA==.Seshymutedme:BAABLgAECn8VAAQOAAgJKhMOgQBYAQAOAAUJpxgOgQBYAQAYAAQJkAowOQDQAAAPAAEJAADbNwAfAAAAAA==.',
Sh='Shadian:BAAALgADCgIJAgAAAA==.Shaldrox:BAAALgADCgEJAQABLgAFFAUJDgAJALoNAA==.Shamanagins:BAAALgAECgEJAQAAAA==.Shannoon:BAAALgAECgMJAwAAAA==.Shimmiiee:BAAALgAECgYJCAAAAA==.Shing:BAABLgAECn8fAAMmAAkJBBkKGABEAgAmAAcJzB0KGABEAgATAAUJ2A0nSwDlAAAAAA==.Shiverr:BAAALgADCgkJGQAAAA==.Shoftìel:BAAALgADCgcJCgAAAA==.Shxt:BAAALgADCgIJAgAAAA==.',
Sk='Skizem:BAAALgADCgIJAgAAAA==.Skott:BAAALgAECgEJAgAAAA==.',
Sl='Sleepyr:BAABLgAECn8ZAAIEAAgJsgtuKQBzAQAEAAgJsgtuKQBzAQAAAA==.Slobkabob:BAAALgAECgEJAQAAAA==.',
Sm='Smol:BAAALgAECgMJBAAAAA==.Smolside:BAAALgADCgEJAQAAAA==.',
Sn='Snowi:BAAALgADCgEJAQABLgAECgQJBgACAAAAAA==.',
So='Solignis:BAACLgAFFH8SAAISAAUJ/yB0AQDvAQASAAUJ/yB0AQDvAQAuAAQKfy8AAxIACQm+JccAANUDABIACQm+JccAANUDABEAAQm1I7gyAGgAAAAA.Soohots:BAAALgAECgUJBQAAAA==.Soular:BAAALgADCgMJAwAAAA==.',
Sp='Sparklehappy:BAAALgAECgUJCQAAAA==.Spiritdurk:BAAALgADCggJDAAAAA==.Spoghasm:BAAALgAECgYJEAAAAA==.Spothoof:BAACLgAFFH8JAAIeAAMJdxXTBgDtAAAeAAMJdxXTBgDtAAAuAAQKfyEAAh4ACAk7IbYMANICAB4ACAk7IbYMANICAAAA.',
St='Stalari:BAAALgAECgQJBQAAAA==.Starshield:BAAALgADCgQJBAABLgAECgUJDAACAAAAAA==.Stcupertino:BAABLgAECn8WAAMVAAgJigXlDgBPAQAVAAgJigXlDgBPAQAGAAEJzwW3VQEoAAAAAA==.Steamedham:BAAALgAECgcJBwAAAA==.Steeljustice:BAAALgADCgUJBQAAAA==.Stellalou:BAAALgAECgEJAQAAAA==.Stormstout:BAAALgADCgIJAgAAAA==.Storri:BAABLgAECn8XAAIhAAYJ0xQ3DAAuAQAhAAYJ0xQ3DAAuAQAAAA==.Stryranger:BAAALgAECgMJAwAAAA==.',
Su='Suehunter:BAAALgADCgcJDwAAAA==.Suturi:BAAALgADCggJCAAAAA==.Suvi:BAAALgADCgEJAwAAAA==.Suzuya:BAAALgADCgcJIQAAAA==.',
Sw='Swiftly:BAAALgAFFAIJAgAAAA==.Swiftmage:BAACLgAFFH8SAAIKAAUJLR8/BwDtAQAKAAUJLR8/BwDtAQAuAAQKfy8AAgoACQlSJtYAAPYDAAoACQlSJtYAAPYDAAAA.',
Sy='Sylvian:BAAALgAECgQJBgAAAA==.Syndrome:BAAALgAECgUJDAAAAA==.Syrelea:BAAALgADCgIJAgAAAA==.Sywren:BAAALgAECgEJAQABLgAECgMJBgACAAAAAA==.',
Sz='Szeto:BAAALgAECgUJDQAAAA==.',
Ta='Talyndis:BAACLgAFFH8RAAMMAAYJeBgEBAD/AQAMAAYJthcEBAD/AQANAAEJnCGOEgBhAAAuAAQKfxwAAwwACQmmIh0DAHcDAAwACQmmIh0DAHcDAA0AAQkyGfs8AEwAAAAA.Tamyr:BAAALgADCgMJAwABLgAECgEJAQACAAAAAA==.Taze:BAAALgAECgQJBAABLgAFFAMJCQANADYPAA==.Tazjiingo:BAAALgAECgMJAwAAAA==.',
Te='Teanie:BAAALgADCgYJBgAAAA==.Tenebrium:BAAALgAECgEJAgAAAA==.Terhali:BAAALgAECgUJBQAAAA==.Terrika:BAAALgAECgUJCAAAAA==.Tetshajeh:BAAALgAECgQJCwAAAA==.',
Th='Theanimal:BAAALgADCgcJCAAAAA==.Therasa:BAAALgAECgEJAQAAAA==.Thewizardguy:BAAALgAECgIJAwAAAA==.Thillarick:BAAALgAECgQJDAAAAA==.Thiss:BAAALgADCgcJBwAAAA==.Thiya:BAAALgAECgcJEgAAAA==.Thorvard:BAAALgAECgUJCgAAAA==.Thromanor:BAAALgADCgcJCwAAAA==.',
Ti='Tirachill:BAAALgAECgEJAQAAAA==.Tiramisú:BAAALgAECgMJAwAAAA==.Tiranmyashol:BAABLgAECn8ZAAISAAcJ8xaXLwDxAQASAAcJ8xaXLwDxAQAAAA==.',
To='Toothdk:BAAALgAECgUJDgAAAA==.Toppo:BAABLgAECn8UAAIkAAgJ0hxBBQClAgAkAAgJ0hxBBQClAgAAAA==.Torfnar:BAAALgAECgQJBAAAAA==.Toxicophobia:BAAALgAECgUJCAAAAA==.',
Tr='Tralle:BAAALgAECgQJCAAAAA==.Treebreak:BAAALgAECgYJDwAAAA==.Treefity:BAAALgADCgIJAgAAAA==.Trinky:BAAALgADCggJEgAAAA==.Troublems:BAAALgAECgQJCAAAAA==.',
Ts='Tshi:BAAALgAECgIJAgAAAA==.',
Tu='Turanx:BAAALgAECgIJAgAAAA==.Tutemkhan:BAAALgAECgQJCAAAAA==.',
Tw='Twigrets:BAAALgAECgUJCQAAAA==.',
Ty='Tyrandrea:BAAALgADCgkJFgAAAA==.',
Ug='Ugîn:BAAALgAECgIJAgAAAA==.',
Um='Umbreona:BAAALgAECgMJAwAAAA==.Umàdbrah:BAABLgAECn8UAAINAAYJ2RnxDgCMAQANAAYJ2RnxDgCMAQAAAA==.',
Un='Unbelievable:BAAALgAECgQJBwAAAA==.Unclechuck:BAAALgADCgQJBwAAAA==.Unholylaezel:BAAALgADCgUJCAAAAA==.',
Va='Valamor:BAAALgAECgYJEwAAAA==.Valencia:BAAALgADCgIJAgAAAA==.Valicela:BAAALgADCgcJEgAAAA==.Vandamage:BAAALgADCgMJAwAAAA==.Vani:BAAALgADCgkJEgAAAA==.Varenea:BAAALgAECgMJAwAAAA==.',
Ve='Veefib:BAAALgAECgcJDwAAAA==.Velhari:BAAALgAECgYJEQABLgAFFAMJBwAFADkZAA==.Velicerus:BAAALgAECgEJAQAAAA==.Velliri:BAAALgAECgMJAwAAAA==.Velvettwitch:BAAALgAECgUJCgAAAA==.Verahla:BAAALgADCgkJHQAAAA==.Vermis:BAAALgAECgQJBwAAAA==.Verona:BAAALgADCgMJAwAAAA==.Veryaverage:BAAALgAECgYJEQAAAA==.Vexation:BAAALgAECgIJAgAAAA==.Vexxd:BAAALgAECgUJDAAAAA==.',
Vi='Vicarious:BAAALgAECgQJBAAAAA==.Vidreaux:BAABLgAECn8YAAIBAAYJfxV0AQB0AQABAAYJfxV0AQB0AQAAAA==.Vipora:BAABLgAECn8gAAMEAAgJXRhwBADLAQAEAAgJXRhwBADLAQAiAAQJ7go1KwDDAAAAAA==.',
Vo='Volaura:BAAALgADCgQJBwAAAA==.Volzara:BAABLgAECn8ZAAIQAAgJ9xMFGgAPAgAQAAgJ9xMFGgAPAgAAAA==.Voìde:BAAALgAECgMJBAAAAA==.',
Vy='Vynesra:BAAALgADCgUJBgAAAA==.',
Wh='Whirz:BAAALgAECgYJCwAAAA==.Whizglizzy:BAAALgADCgQJBAAAAA==.Whosethetank:BAAALgADCgcJEgAAAA==.',
Wm='Wmz:BAAALgAECgQJBwAAAA==.',
Wo='Wolfíe:BAAALgAECgEJAQAAAA==.',
Ww='Wwalle:BAAALgAECgUJBwABLgAECgYJFAAcAIkWAA==.',
Xe='Xenarra:BAAALgADCgUJBQAAAA==.',
Xz='Xzavier:BAAALgAECgEJAQAAAA==.',
Ya='Yandros:BAAALgADCgIJAgAAAA==.Yansaa:BAAALgAECgQJCwAAAA==.Yasutora:BAAALgADCgYJCgABLgAECgcJFQAZAMsfAA==.',
Yf='Yfelshammy:BAABLgAECn8aAAIJAAgJlAylOwCTAQAJAAgJlAylOwCTAQAAAA==.',
Yo='Yogiebear:BAAALgADCgUJBQAAAA==.Yogsøthoth:BAAALgADCgYJBgAAAA==.',
Yr='Yrsea:BAAALgADCgIJAgAAAA==.',
Yu='Yubel:BAAALgAECgQJBAAAAA==.',
Za='Zaevenia:BAAALgADCggJCAAAAA==.Zakka:BAAALgADCgQJBgAAAA==.Zanebusby:BAAALgAECgYJDQAAAA==.Zannahh:BAAALgAECgYJCgAAAA==.Zaraa:BAABLgAECn8UAAILAAYJriEECgAzAgALAAYJriEECgAzAgAAAA==.Zaraë:BAAALgAECgEJAQAAAA==.Zatharis:BAAALgAECgQJBAAAAA==.',
Ze='Zepp:BAAALgAECgEJAgAAAA==.Zerax:BAAALgAECgEJAQAAAA==.Zeroshaman:BAAALgADCgkJDgAAAA==.',
Zz='Zzella:BAABLgAECn8iAAMVAAgJZSNlAQC1AgAVAAgJZSNlAQC1AgAGAAMJowTEEgFxAAAAAA==.',
['Ða']='Ðabzilla:BAABLgAECn8ZAAMVAAgJThclBwDbAQAVAAcJpxglBwDbAQAGAAEJqgvKZAAqAAAAAA==.',
['Ðr']='Ðracotalon:BAAALgAECgYJCgAAAA==.',
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
