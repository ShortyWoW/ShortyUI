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

local lookup = {'Hunter-Survival','Hunter-Marksmanship','Druid-Balance','Druid-Restoration','Warrior-Fury','Unknown-Unknown','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','DemonHunter-Devourer','Paladin-Retribution','Hunter-BeastMastery','Priest-Holy','Priest-Discipline','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Vengeance','DemonHunter-Havoc','DeathKnight-Unholy','Shaman-Elemental','Shaman-Restoration','Monk-Mistweaver','Monk-Windwalker','Warrior-Arms','Monk-Brewmaster','Mage-Arcane','Mage-Frost','Mage-Fire','Druid-Feral','DeathKnight-Blood','Druid-Guardian','Rogue-Assassination','Rogue-Subtlety','Paladin-Holy','Priest-Shadow','Warrior-Protection','Paladin-Protection','Evoker-Preservation','DeathKnight-Frost','Rogue-Outlaw','Shaman-Enhancement',}
local provider = {region='US',realm='Hellscream',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aarix:BAABLgAECn8hAAMBAAgJ8g2aCgC3AQABAAgJ8g2aCgC3AQACAAEJCgCznAACAAAAAA==.',
Ac='Achmed:BAAALgAECgEJAQAAAA==.',
Ad='Adaptabull:BAABLgAECn8bAAMDAAgJShmTDwCZAQADAAgJShmTDwCZAQAEAAIJIxW1rgBoAAAAAA==.Adari:BAAALgADCgMJAwAAAA==.Adune:BAAALgADCgQJBAAAAA==.',
Ae='Aelinessa:BAAALgAECgYJCwAAAA==.Aeo:BAAALgAECgcJEwABLgAECggJIQAEAFsgAA==.Aerodox:BAAALgAECgIJAgAAAA==.',
Ai='Aiel:BAAALgAECgcJEQABLgAECgcJHQAFAGgaAA==.',
Al='Albedò:BAAALgAECgIJAwAAAA==.Aldrîch:BAAALgADCgMJAwAAAA==.Allyra:BAAALgADCgIJAgABLgAECgIJBQAGAAAAAA==.Allzaz:BAAALgAECgQJDQABLgAECggJGgAHAOwUAA==.Allzera:BAABLgAECn8aAAQHAAgJ7BTADgBEAQAHAAYJrQ/ADgBEAQAIAAcJ3hItiwBDAQAJAAQJog+aEwCFAAAAAA==.Alric:BAAALgAECgYJDAAAAA==.',
Am='Amalei:BAAALgADCgYJBgAAAA==.Amberness:BAAALgAECgIJAgABLgAFFAEJAQAGAAAAAA==.Ammaria:BAAALgADCgUJBQAAAA==.Amorose:BAAALgAECgcJCQAAAA==.',
An='Anastassia:BAAALgADCgkJEQABLgAECgQJBAAGAAAAAA==.Andol:BAAALgADCgUJBQABLgAECgYJEAAGAAAAAA==.Anduwyn:BAAALgADCgIJAgAAAA==.Anezra:BAAALgAECgEJAQAAAA==.Angelmack:BAAALgAECggJBwAAAA==.Anibella:BAABLgAECn8eAAIKAAgJfxsyEwDRAQAKAAgJfxsyEwDRAQAAAA==.Antons:BAAALgADCgkJEAAAAA==.Anuke:BAAALgAECgYJCQAAAA==.',
Ap='Aphlykted:BAAALgADCgYJBgAAAA==.',
Ar='Arbinu:BAAALgADCgMJAwAAAA==.Arflane:BAAALgADCgEJAQAAAA==.Argenta:BAAALgADCgEJAQAAAA==.Arkhlight:BAABLgAECn8XAAILAAgJ8hwEEwAiAgALAAgJ8hwEEwAiAgAAAA==.Arkhmonk:BAAALgAFFAEJAQAAAA==.Arkillos:BAAALgAECgEJAgAAAA==.Armerous:BAAALgADCgMJAwAAAA==.Arnlok:BAAALgADCgMJAwAAAA==.Arrowhoof:BAABLgAFFH8GAAIMAAIJDAjqGgCZAAAMAAIJDAjqGgCZAAAAAA==.Arthurian:BAAALgADCgUJEQAAAA==.',
As='Ashmorph:BAAALgADCgYJCAAAAA==.Ashpriest:BAABLgAECn8eAAMNAAgJmhlLCwDwAQANAAgJLRlLCwDwAQAOAAQJ6hZEGgAUAQAAAA==.Ashýra:BAABLgAECn8nAAINAAkJmw0MDgDBAQANAAkJmw0MDgDBAQAAAA==.Asphyxxed:BAAALgAECgEJAQAAAA==.Asterisk:BAABLgAECn8oAAIMAAgJXBsCDwAgAgAMAAgJXBsCDwAgAgAAAA==.Asya:BAAALgAECgYJBQAAAA==.',
At='Ataxica:BAAALgAECgEJAQAAAA==.Atlas:BAAALgAECgMJAwAAAA==.Attanu:BAAALgADCgIJAgAAAA==.Attilathepun:BAAALgADCgcJBwAAAA==.',
Au='Augrizia:BAAALgADCgMJBQAAAA==.Auriêl:BAAALgAECgIJAgAAAA==.',
Az='Azastra:BAABLgAECn8WAAMPAAYJVwxtBwAXAQAPAAYJVwxtBwAXAQAQAAYJVAfJIwDoAAAAAA==.Azer:BAAALgADCgYJBgAAAA==.',
['Añ']='Aña:BAABLgAECn8WAAQRAAcJiiKuAgAIAgARAAcJiiKuAgAIAgASAAIJ1BTZWQB8AAAKAAEJfwu75gArAAAAAA==.Añarchist:BAAALgADCggJFQABLgAECggJFgARAIoiAA==.',
Ba='Babyymonster:BAAALgAECgMJAwAAAA==.Badboii:BAAALgADCgMJAwAAAA==.Baelzharon:BAAALgAECgYJEwAAAA==.Baerenger:BAAALgAECggJDwAAAA==.Baern:BAAALgAECgYJDwABLgAECggJDwAGAAAAAA==.Bagelpanda:BAAALgADCgMJAwAAAA==.Balròg:BAAALgADCgEJAQAAAA==.Barrthas:BAABLgAFFH8GAAITAAMJFxqkKQAXAQATAAMJFxqkKQAXAQABLgABCgQJBAAGAAAAAA==.Basalt:BAABLgAECn8eAAIMAAgJzxhbGADQAQAMAAgJzxhbGADQAQAAAA==.Bastenwode:BAAALgAECgQJCQAAAA==.',
Bb='Bbye:BAAALgAECgEJAQAAAA==.',
Be='Bearmyload:BAAALgADCgUJBQABLgAECgcJCwAGAAAAAA==.Beastwrld:BAAALgADCgcJGgAAAA==.Becký:BAABLgAECn8WAAIMAAcJnBxnGgDCAQAMAAcJnBxnGgDCAQAAAA==.Beeflomein:BAAALgADCgEJAQAAAA==.Beroan:BAAALgADCgYJBgAAAA==.',
Bi='Bigcøøkie:BAAALgADCgYJBwAAAA==.Bighealin:BAAALgAECgQJBAAAAA==.Bigjim:BAABLgAECn8VAAMIAAkJKx7yMwA8AgAIAAkJKx7yMwA8AgAJAAEJNQRLbQA6AAAAAA==.Biglul:BAAALgAECgMJAwABLgAFFAQJDAAFALoZAA==.Bigolcrities:BAAALgADCgEJAQAAAA==.Bivivi:BAAALgAECgQJBwAAAA==.',
Bj='Bjorn:BAAALgADCgQJBAAAAA==.',
Bl='Blackmagma:BAAALgAECgEJAQABLgAECggJGAAUAPMUAA==.Blackpiink:BAAALgAFFAEJAQAAAA==.Blackppink:BAACLgAFFH8HAAIVAAMJrw7MEADiAAAVAAMJrw7MEADiAAAuAAQKfx8AAhUACQlDHIcLAMYCABUACQlDHIcLAMYCAAAA.Blackppinkk:BAAALgAFFAIJAgAAAA==.Bladefi:BAABLgAECn8aAAMSAAcJwCU7AgCaAgASAAcJwCU7AgCaAgAKAAYJnB1nPgD7AQAAAA==.Blamo:BAABLgAECn8eAAIEAAgJnxWqEgD0AQAEAAgJnxWqEgD0AQAAAA==.Blesedtogoon:BAAALgAECgMJBQAAAA==.Bloodbunny:BAAALgAECgQJBwAAAA==.Bluddbeard:BAAALgAECgkJCAAAAA==.',
Bm='Bmoneycuh:BAABLgAECn8bAAIIAAgJ6BmuEQAXAgAIAAgJ6BmuEQAXAgAAAA==.',
Bo='Boozerbear:BAAALgAECgkJAwAAAA==.Bornite:BAAALgADCgkJFQAAAA==.Bosstradamus:BAAALgAECgkJEAABLgAFFAIJAgAGAAAAAA==.Bottombenoit:BAAALgADCgYJCgAAAA==.',
Br='Brewmanfu:BAABLgAECn8sAAMWAAkJThmOGAD5AQAWAAkJThmOGAD5AQAXAAQJIwkKXQCcAAAAAA==.Brewmaster:BAAALgAECgEJAQAAAA==.Brickaton:BAABLgAECn8VAAIMAAcJYRFMMABPAQAMAAcJYRFMMABPAQAAAA==.Brickdrag:BAAALgADCgYJBgABLgAECgcJFQAMAGERAA==.Brionaimina:BAAALgADCgQJBAAAAA==.Brocknor:BAABLgAECn8aAAIYAAcJPBmKBQDPAQAYAAcJPBmKBQDPAQAAAA==.Brook:BAAALgADCgcJBwAAAA==.Brucebanners:BAAALgAECgEJAgABLgAFFAMJBAAKAHcLAA==.Bruiseli:BAABLgAECn8VAAMZAAYJTAStKgDAAAAZAAYJTAStKgDAAAAXAAMJTALFbwBTAAAAAA==.Brujilda:BAAALgAECgUJCQAAAA==.Brèdren:BAABLgAECn8+AAIWAAgJZCKuAQAeAwAWAAgJZCKuAQAeAwAAAA==.Brüh:BAAALgAECggJDAAAAA==.',
Bu='Bucklebury:BAAALgADCgEJAQAAAA==.Bullogna:BAAALgAECgIJAgAAAA==.Burbon:BAAALgADCgMJAwABLgAECggJHAAXAKoeAA==.Burstinatrix:BAAALgADCgEJAQAAAA==.Burtina:BAAALgAECgEJAQAAAA==.Butterdtoast:BAEBLgAECn8UAAIXAAcJURAiEwBYAQAXAAcJURAiEwBYAQAAAA==.',
['Bë']='Bëâst:BAAALgAECgIJAgAAAA==.',
Ca='Caboose:BAABLgAECn8fAAQaAAgJRR6XAgBqAgAaAAcJRR6XAgBqAgAbAAMJaApoGgHKAAAcAAMJgBFRCQC+AAAAAA==.Cadius:BAAALgADCgMJAwAAAA==.Caimera:BAAALgAECgEJAQAAAA==.Caledor:BAAALgAECgMJBAAAAA==.Calindrel:BAAALgAECggJEQAAAA==.Caraway:BAAALgAECgUJBQAAAA==.Carcus:BAAALgADCggJCAAAAA==.Carysa:BAAALgADCgcJFAAAAA==.',
Ce='Celebrindal:BAAALgADCgkJHQAAAA==.Celticlore:BAAALgADCgkJKQAAAA==.Cerrvantes:BAAALgADCgMJAwAAAA==.Cesarius:BAAALgAECgQJDgAAAA==.',
Ch='Chappellroan:BAAALgAECgQJBAAAAA==.Charlemange:BAAALgADCgMJAwAAAA==.Charvein:BAAALgAECgQJBAAAAA==.Chernaboz:BAAALgAECgcJEgAAAA==.Chevelot:BAAALgADCgYJDAAAAA==.Chibbo:BAABLgAECn8fAAIdAAkJJQiDBgCeAQAdAAkJJQiDBgCeAQAAAA==.Chiblet:BAAALgAECgIJAgAAAA==.Chillblain:BAAALgADCgEJAQAAAA==.Chippendale:BAAALgADCgkJGwAAAA==.Chondre:BAABLgAECn8YAAIIAAgJ0BkQHADMAQAIAAgJ0BkQHADMAQAAAA==.Chrigs:BAAALgAECgYJBwAAAA==.Chrispbacon:BAAALgADCgYJBgAAAA==.',
Co='Combustdeez:BAAALgADCgUJBQABLgAFFAcJCQAIACkdAA==.Conrad:BAAALgADCgUJBQAAAA==.Copperknight:BAABLgAECn8UAAITAAcJpQngXQDtAAATAAcJpQngXQDtAAAAAA==.Corenthos:BAABLgAECn8jAAMTAAgJ6iEpBwCrAgATAAgJ6iEpBwCrAgAeAAEJkRLcRgAsAAAAAA==.Cornelia:BAAALgAECgQJBAAAAA==.Cortanna:BAAALgADCgYJDgAAAA==.',
Cr='Cranker:BAAALgAECgMJBQAAAA==.Crashedot:BAAALgAECgQJBwAAAA==.Crazymoron:BAAALgADCggJCAAAAA==.Creselia:BAAALgAECgYJEgAAAA==.Criminel:BAAALgADCgEJAQAAAA==.Cropduzzter:BAAALgADCgQJBAAAAA==.Crum:BAABLgAECn8XAAMDAAcJ0QjXIgDpAAADAAcJ8gfXIgDpAAAfAAMJ9wRbHABAAAAAAA==.Cryptnotic:BAAALgADCgIJAgAAAA==.',
Cu='Cuddlerz:BAAALgAECgIJAgAAAA==.Cutthrøat:BAAALgAECgQJBQAAAA==.',
Cy='Cypherrellik:BAAALgAECgYJCwABLgAECgcJFAASAJsQAA==.',
['Câ']='Câp:BAAALgAECgcJCQAAAA==.',
Da='Dablackmasta:BAABLgAECn8XAAIFAAgJbQ5LGwBWAQAFAAgJbQ5LGwBWAQAAAA==.Daftfunk:BAAALgADCggJCAAAAA==.Dagthunderer:BAAALgAECgYJCgAAAA==.Daidonks:BAAALgAECgMJBAAAAA==.Dakkenrahl:BAAALgAECgQJCQAAAA==.Dalistra:BAAALgAECgIJBQAAAA==.Dalweaver:BAAALgADCgMJAwABLgAECgIJBQAGAAAAAA==.Dalzz:BAAALgADCgYJBgABLgAECgIJBQAGAAAAAA==.Dantes:BAAALgADCgkJFAAAAA==.Dar:BAAALgAECgQJBwAAAA==.Darkaires:BAAALgAECgkJBgAAAA==.Darkflame:BAAALgAECgcJEAAAAA==.Darksidedbro:BAAALgADCgkJEQAAAA==.Darthvaeder:BAAALgAECgUJDAAAAA==.Davee:BAAALgADCgcJBwAAAA==.',
Dc='Dcpt:BAAALgADCgcJFAAAAA==.',
De='Deadgeinside:BAAALgAECgQJBgAAAA==.Deadgnome:BAAALgAECgIJAgABLgAECgYJFwAZAEMTAA==.Deathrose:BAAALgADCgkJCgAAAA==.Deathstomper:BAAALgAECgQJBgAAAA==.Delnarian:BAABLgAECn8bAAILAAgJZxx7NwBFAgALAAgJZxx7NwBFAgAAAA==.Demondono:BAABLgAECn8ZAAISAAcJehMzDAB5AQASAAcJehMzDAB5AQAAAA==.Desmorphia:BAAALgAECgEJAQAAAA==.Destruir:BAAALgADCgkJCgAAAA==.Desy:BAAALgADCgQJBAABLgAECgcJFAAIAKIlAA==.Dethomonic:BAAALgADCgkJCQAAAA==.Devomo:BAABLgAECn8fAAIKAAcJXyDzFADCAQAKAAcJXyDzFADCAQAAAA==.Devoutsquirl:BAAALgADCgYJBgABLgAECgcJEwAGAAAAAA==.Deyedora:BAAALgAECgYJCwAAAA==.Deyjavaknadi:BAAALgADCgMJAwAAAA==.',
Di='Diegodruida:BAAALgADCgUJBQAAAA==.Dilligafnope:BAAALgADCgkJEgAAAA==.Dinkster:BAABLgAECn8VAAMDAAgJXgnYIAD3AAADAAgJXgnYIAD3AAAEAAMJ0gSKsABkAAAAAA==.Dinohunter:BAABLgAECn8WAAIMAAcJmSFTDAA+AgAMAAcJmSFTDAA+AgAAAA==.Dinokat:BAAALgADCgUJBgABLgAECggJKAAIAOcXAA==.Dirtslinger:BAAALgAECgMJAwAAAA==.Disabler:BAACLgAFFH8JAAIIAAcJKR1EAABUAgAIAAcJKR1EAABUAgAuAAQKfyUAAwgACQlBJj4AAIYDAAgACQlBJj4AAIYDAAkAAQnvIdVZAGEAAAAA.Discotits:BAAALgAECgEJAQAAAA==.',
Do='Dobyclease:BAAALgAECgIJAgAAAA==.Dokesa:BAABLgAECn8VAAMTAAcJ0R3eQwAqAgATAAYJQyHeQwAqAgAeAAEJlwzjRwApAAAAAA==.Dolfratt:BAAALgAECggJEAABLgAECgkJLAAWAE4ZAA==.Dooknukem:BAAALgADCgYJBgAAAA==.Doomguard:BAAALgAECgMJAwAAAA==.Dorimane:BAAALgAECgcJEwAAAQ==.Dorlock:BAABLgAECn8YAAIHAAcJFgbHEAAhAQAHAAcJFgbHEAAhAQAAAA==.Dortivi:BAAALgAECgEJAQAAAA==.Dotdôtdot:BAAALgADCgIJAgAAAA==.Dotrastraez:BAAALgAECgEJAQAAAA==.Dotvader:BAAALgAECgcJDAAAAA==.',
Dr='Draklee:BAAALgAECgEJAgAAAA==.Draxestraza:BAAALgADCgcJFwAAAA==.Draykey:BAAALgAECgQJBQABLgAECgcJIgAEAC4eAA==.Draykeyy:BAABLgAECn8iAAIEAAcJLh4mIgA1AgAEAAcJLh4mIgA1AgAAAA==.Dred:BAAALgAECgEJAQAAAA==.Dredwarrior:BAABLgAECn8XAAMYAAkJIRAoEAAKAQAFAAYJSBACXgA3AQAYAAYJjgwoEAAKAQAAAA==.Drenlei:BAAALgAECgcJBwAAAA==.Drood:BAAALgAECgEJAQAAAA==.Drotara:BAABLgAECn8UAAIMAAcJKx7iEAAOAgAMAAcJKx7iEAAOAgAAAA==.Drprodigy:BAABLgAECn8iAAIKAAkJzRRaPAADAgAKAAkJzRRaPAADAgAAAA==.Drunkbaby:BAABLgAECn8UAAILAAkJ8CCoEQAEAwALAAkJ8CCoEQAEAwAAAA==.',
Dy='Dynasty:BAAALgAECgIJAgAAAA==.Dyrcyn:BAAALgAECgEJAQAAAA==.',
['Dà']='Dàddy:BAAALgAECgEJAQAAAA==.Dànger:BAAALgAECgkJCAAAAA==.',
Ed='Edrius:BAAALgAECgMJAwAAAA==.Edroh:BAABLgAECn8ZAAIbAAcJtgnfUwA4AQAbAAcJtgnfUwA4AQAAAA==.',
Eh='Ehsera:BAAALgADCgUJBgAAAA==.',
Ei='Eidur:BAABLgAECn8YAAMgAAkJAhmEBQBoAQAgAAkJshiEBQBoAQAhAAUJ7BZcPAA4AQAAAA==.',
El='Elando:BAAALgAECgQJBAAAAA==.Elegies:BAABLgAECn8oAAIKAAkJeh4AEADxAQAKAAkJeh4AEADxAQAAAA==.Elemefayoh:BAAALgAECgEJAQABLgAECgYJCQAGAAAAAA==.Elfater:BAAALgAECgMJAwAAAA==.Eliarace:BAAALgADCgMJAwAAAA==.Eljeffesan:BAAALgADCgcJFwAAAA==.Elspeth:BAAALgADCgYJBgABLgAECgcJFAAMACseAA==.Elythria:BAAALgAECgQJBwAAAA==.',
Em='Emagonadye:BAACLgAFFH8LAAIZAAQJRxsTBgBwAQAZAAQJRxsTBgBwAQAuAAQKfxUAAhkACAmjJFQEAEcDABkACAmjJFQEAEcDAAAA.Emlee:BAAALgADCgIJAgAAAA==.Emporersmaug:BAAALgADCgEJAQAAAA==.',
En='Endgamer:BAAALgAECgYJBgAAAA==.Endugu:BAAALgAECgcJDwAAAA==.Enflamee:BAABLgAECn8VAAMbAAgJaBnDHwDuAQAbAAgJaBnDHwDuAQAaAAEJUwzNHQA2AAAAAA==.Enforcer:BAABLgAECn8YAAMIAAgJfxtGPAA+AQAIAAcJORpGPAA+AQAJAAMJ+xTbOgDJAAAAAA==.Engath:BAAALgAECgYJDAABLgAECggJFQAbAGgZAA==.',
Er='Erikprince:BAAALgADCgEJAgAAAA==.Erosonia:BAAALgAECgQJCQAAAA==.Erso:BAAALgADCgYJCAAAAA==.',
Es='Espresso:BAAALgAECgcJEAAAAA==.',
Et='Eternalpaín:BAABLgAECn8fAAILAAgJyhvjJwCjAQALAAgJyhvjJwCjAQAAAA==.',
Ev='Evanee:BAAALgAECgcJEwAAAA==.Evanrude:BAAALgAECgMJAwAAAA==.',
Ez='Ezykeul:BAAALgAECgQJCQAAAA==.',
Fa='Fal:BAABLgAECn8VAAMMAAkJuQ+ATwB6AQAMAAgJow+ATwB6AQACAAUJUAjqWgDXAAAAAA==.Falcyon:BAAALgADCgMJAwAAAA==.Fallenson:BAAALgAECgEJAgAAAA==.',
Fe='Felbrooks:BAAALgADCgkJFQAAAA==.Felmommy:BAAALgADCgcJAQAAAA==.Felsông:BAAALgADCgcJBwAAAA==.Fendretta:BAABLgAECn8hAAIMAAgJpxZYEwD3AQAMAAgJpxZYEwD3AQAAAA==.',
Fi='Firefawkes:BAAALgAECgQJBAAAAA==.Fistbump:BAAALgADCgYJDAAAAA==.Fivepiece:BAAALgADCgcJBwAAAA==.Fixzie:BAABLgAECn8UAAIFAAgJtgoJFgCDAQAFAAgJtgoJFgCDAQAAAA==.',
Fl='Flah:BAAALgAECgkJDAAAAA==.Flip:BAAALgAECgcJBwAAAA==.Flizrak:BAAALgAFFAEJAQABLgAFFAYJGQAbADMiAA==.',
Fo='Forestflex:BAAALgAECgYJBgAAAA==.Foxstrazagos:BAAALgADCgkJCwAAAA==.',
Fr='Friggnar:BAAALgADCgYJBwAAAA==.Frostsalad:BAAALgADCgQJBAAAAA==.Frostynugz:BAAALgADCgYJCQAAAA==.',
Fu='Fulta:BAABLgAECn8dAAICAAgJFhz7AgAJAgACAAgJFhz7AgAJAgAAAA==.',
Fy='Fyra:BAAALgADCggJCAABLgAFFAMJBgALAHQFAA==.',
['Fí']='Fírnen:BAAALgAECgQJBwAAAA==.',
Ga='Gailz:BAAALgADCgQJBAAAAA==.Gammb:BAAALgAECgEJAQAAAA==.Garadin:BAABLgAECn8bAAIDAAgJOhHSDwCWAQADAAgJOhHSDwCWAQAAAA==.Garcona:BAAALgAFFAEJAgAAAA==.Garqman:BAAALgADCgUJBQAAAA==.Garwa:BAAALgAECgQJCgAAAA==.',
Ge='Geniver:BAAALgAECgQJCgAAAA==.Gerken:BAAALgAECgIJAgAAAA==.Gerkenator:BAAALgAECgYJCQAAAA==.Gerla:BAAALgAECgcJEgAAAA==.',
Gh='Ghettoshout:BAAALgAECgMJBAAAAA==.',
Gi='Gialania:BAABLgAECn8YAAMDAAcJyQcSHwAEAQADAAcJyQcSHwAEAQAEAAMJjABw4wAiAAAAAA==.Gilgameshh:BAAALgADCgkJEAAAAA==.Girthbrook:BAAALgADCgcJCAAAAA==.Girthbrooks:BAAALgADCgQJBAAAAA==.Girthtrude:BAABLgAECn8ZAAIKAAgJeAyRLwAlAQAKAAgJeAyRLwAlAQAAAA==.',
Gl='Glaivertoss:BAAALgAECgcJCQAAAA==.Glorythighs:BAAALgADCgEJAQAAAA==.Glycerol:BAAALgADCgUJBQAAAA==.',
Go='Goblincox:BAAALgAECgYJEgAAAA==.Gomory:BAAALgAECgQJCgAAAA==.Gondark:BAAALgAECgQJBgAAAA==.Goobly:BAABLgAECn8cAAIhAAYJsReTLACaAQAhAAYJsReTLACaAQAAAA==.Gooseblade:BAAALgADCgUJBQAAAA==.Goregrimm:BAAALgAECgMJBAAAAA==.Gorgoz:BAAALgADCgEJAQAAAA==.Gorgrim:BAAALgADCgMJAwAAAA==.',
Gr='Gregòr:BAAALgAECgkJBQAAAA==.Gretchen:BAABLgAECn8vAAMTAAgJXhlRGQDwAQATAAgJXhlRGQDwAQAeAAQJbAirNgCMAAAAAA==.Greywing:BAAALgAECgUJBQAAAA==.Greywolf:BAABLgAECn8gAAIVAAkJWxkIDQAcAgAVAAkJWxkIDQAcAgAAAA==.Grezin:BAAALgADCgEJAQAAAA==.Grimlight:BAABLgAFFH8JAAILAAMJ2hzMEQAXAQALAAMJ2hzMEQAXAQABLgAFFAcJEwATADcaAA==.Grimshaw:BAAALgAECgYJBgAAAA==.Grimtorr:BAAALgADCgMJAwAAAA==.Ground:BAAALgAECgYJCAAAAA==.Grymlee:BAAALgAECgQJCgAAAA==.Grëgor:BAAALgAECgQJBAAAAA==.',
Gu='Guinènvere:BAAALgAECgYJEAAAAA==.',
['Gä']='Gärry:BAAALgAECgEJAQAAAA==.',
['Gö']='Gökù:BAAALgADCgQJBAAAAA==.',
Ha='Haedes:BAAALgAECgMJAwABLgAECgYJEAAGAAAAAA==.Haktori:BAAALgAECgYJBwAAAA==.Hammerknee:BAAALgAECgcJDwAAAA==.Hariku:BAAALgAECgQJCQAAAA==.Harleii:BAAALgAECgcJDgAAAA==.Harlequins:BAAALgAECgEJAQAAAA==.Harmonix:BAAALgAECgkJBgAAAA==.Harrow:BAAALgAECgUJCgAAAA==.Hastler:BAAALgADCgkJCQAAAA==.Hawt:BAAALgAECgEJBQAAAA==.',
He='Hearge:BAABLgAECn8dAAMiAAkJzBtWDQCuAgAiAAkJzBtWDQCuAgALAAYJVQgIuwAQAQAAAA==.Heckatae:BAAALgAECgYJDgAAAA==.Hellborne:BAAALgADCgIJAgAAAA==.Hellhawk:BAABLgAECn8VAAIiAAgJ2xIkDwDuAQAiAAgJ2xIkDwDuAQAAAA==.Helwe:BAAALgAECgMJBAAAAA==.Heptandew:BAAALgAECgYJCAAAAA==.',
Hi='Hikkio:BAAALgADCgMJAwAAAA==.',
Ho='Holycheeks:BAAALgADCgYJBgAAAA==.Holychib:BAAALgAECgYJCAAAAA==.Holypho:BAAALgADCgYJDAAAAA==.Holysheet:BAAALgAECgYJCAAAAA==.Holystan:BAAALgAECgYJEAAAAA==.Hondoe:BAAALgAECgQJBQAAAA==.Honorable:BAAALgADCgEJAQABLgAECgkJLAAWAE4ZAA==.Hoshino:BAAALgADCgYJBwABLgAECgMJAwAGAAAAAA==.Hoshiyoru:BAAALgADCggJFAAAAA==.Houki:BAABLgAECn8WAAILAAcJUQn7UgAVAQALAAcJUQn7UgAVAQAAAA==.',
Hp='Hpylorii:BAAALgAECgYJEgAAAA==.',
Ht='Htownhunter:BAAALgAECgQJBwAAAA==.Htownprot:BAAALgAFFAIJAwAAAA==.',
Hu='Hungovertank:BAACLgAFFH8TAAIZAAUJTyGWBgBpAQAZAAUJTyGWBgBpAQAuAAQKfzEAAhkACAmIJRIEAEwDABkACAmIJRIEAEwDAAAA.Hungzilla:BAABLgAECn8ZAAMQAAcJYhbBHgDOAQAQAAcJYhbBHgDOAQAPAAMJvw+5LgCiAAAAAA==.Huntered:BAAALgADCgIJAQAAAA==.Huntfromhell:BAABLgAECn8SAAMSAAcJqB6zCQCnAQASAAYJUxyzCQCnAQARAAQJpxqLDQC5AAAAAA==.Hurkano:BAAALgADCgUJCQAAAA==.',
Ig='Ignisfatuus:BAAALgAECgcJCwAAAA==.',
Il='Ilarion:BAAALgAECgQJBAAAAA==.Illio:BAAALgAECgUJCAAAAA==.Illyasviel:BAAALgAECgEJAgAAAA==.',
Im='Imarea:BAABLgAECn8ZAAIbAAYJQwZreQDjAAAbAAYJQwZreQDjAAAAAA==.Impirious:BAABLgAECn8UAAMeAAYJIgt4GAC5AAAeAAYJIgt4GAC5AAATAAQJpQZv6ACvAAAAAA==.Imppimp:BAAALgAECgEJAgAAAA==.Imtryntotank:BAABLgAECn8cAAIiAAgJzwlqJAAkAQAiAAgJzwlqJAAkAQAAAA==.Imyx:BAABLgAECn8WAAITAAYJrhnEMwBqAQATAAYJrhnEMwBqAQAAAA==.',
In='Infamuspikel:BAAALgAFFAEJAQAAAA==.Infel:BAAALgAECgkJDQAAAA==.Inkkish:BAAALgAECgUJCAAAAA==.Innovates:BAAALgAECgQJDAAAAA==.Innowar:BAAALgADCgYJBgAAAA==.Interstellar:BAAALgAECgEJAQAAAA==.Intervene:BAAALgADCgMJAwABLgAECggJHwALAMobAA==.Invictus:BAABLgAECn8WAAIbAAgJQw0NNwCKAQAbAAgJQw0NNwCKAQAAAA==.',
Io='Iota:BAAALgAECgYJEwAAAA==.',
Ir='Irminarae:BAABLgAECn8aAAMIAAcJyQ9JOABLAQAIAAcJyQ9JOABLAQAJAAEJPgM1egAoAAAAAA==.',
Is='Isa:BAAALgADCgEJAQAAAA==.Isaßeau:BAAALgAECggJCAAAAA==.',
Ja='Jandoar:BAABLgAECn8WAAIbAAYJ1QUxcwDyAAAbAAYJ1QUxcwDyAAAAAA==.Jarlen:BAAALgADCgcJCgAAAA==.Jasmil:BAAALgADCgUJCAAAAA==.Jaylah:BAAALgADCgUJBgAAAA==.',
Je='Jezala:BAAALgADCgkJGQAAAQ==.',
Ji='Jiq:BAAALgADCgUJBwAAAA==.',
Jo='Johli:BAAALgADCgkJCQAAAA==.',
['Jö']='Jördyn:BAAALgADCgMJAwAAAA==.',
Ka='Kabilos:BAAALgAECgYJCQAAAA==.Kaboòm:BAABLgAECn8hAAIbAAgJcRCqfQDWAQAbAAgJcRCqfQDWAQAAAA==.Kaedian:BAAALgADCgQJBAABLgAECggJHAAXAKoeAA==.Kaelthazad:BAAALgADCgEJAQAAAA==.Kagamai:BAAALgADCgUJBQAAAA==.Kagaramar:BAAALgAECgEJAQAAAA==.Kalesmora:BAABLgAECn8XAAIYAAcJExoqBQDcAQAYAAcJExoqBQDcAQAAAA==.Kaluu:BAAALgAECgEJAQABLgAECgEJAgAGAAAAAA==.Kamikaze:BAABLgAECn8ZAAISAAgJIQ8JDAB8AQASAAgJIQ8JDAB8AQAAAA==.Kaorî:BAAALgADCgEJAQAAAA==.Karlov:BAABLgAECn8OAAIjAAcJAhPRJQCpAQAjAAcJAhPRJQCpAQAAAA==.Kassima:BAAALgADCgEJAQAAAA==.Katebush:BAAALgAECgIJAgAAAA==.Kaydahlia:BAAALgAECgEJAQAAAA==.',
Ke='Keheo:BAAALgAECgEJAQAAAA==.Kelastalan:BAAALgADCgIJAgAAAA==.Kelithiena:BAAALgADCgQJCAAAAA==.',
Kh='Khaziel:BAAALgAECgUJBQAAAA==.Kheims:BAAALgAECgQJBAAAAA==.Khri:BAAALgAECgIJAgAAAA==.Khuzdul:BAAALgAECgEJAQAAAA==.',
Ki='Kidcat:BAAALgAECgMJBQAAAA==.Kiddemon:BAAALgADCgcJCAAAAA==.Killduran:BAAALgAECggJDwAAAA==.Kimiyo:BAAALgADCgcJCAAAAA==.Kimpossumble:BAAALgAECgMJAwAAAA==.Kinetic:BAAALgADCgkJEAAAAA==.Kirasha:BAAALgADCgIJAgAAAA==.',
Kl='Kleopatra:BAABLgAECn8YAAMXAAYJtwV2LACaAAAXAAYJtwV2LACaAAAZAAIJ8gIYhAA/AAAAAA==.Klunt:BAAALgADCgcJCAABLgAECgYJEwAGAAAAAA==.',
Kn='Knitehunt:BAAALgAECgUJBQAAAA==.Knives:BAAALgAECgQJCwAAAA==.',
Ko='Kochiyo:BAAALgADCgcJEwAAAA==.Korgal:BAAALgAECgIJAgAAAA==.Kortar:BAAALgAECgQJBAAAAA==.Kotros:BAAALgAECgEJAQAAAA==.',
Kr='Kracked:BAAALgAECgMJBAABLgAECgQJDgAGAAAAAA==.Kreigan:BAAALgADCgkJCQAAAA==.Krelid:BAAALgADCgkJEAABLgAECgYJGQAWABggAA==.Krellyroll:BAABLgAECn8ZAAMWAAYJGCBgCQAaAgAWAAYJGCBgCQAaAgAXAAIJZRMeZAB9AAAAAA==.Krelthyr:BAAALgADCgkJCQABLgAECgYJGQAWABggAA==.Krumm:BAABLgAECn8iAAIkAAgJYwcxEAAdAQAkAAgJYwcxEAAdAQAAAA==.Krumpas:BAAALgADCgcJDgAAAA==.Kryvea:BAAALgADCggJCAAAAA==.',
Ku='Kuhne:BAAALgADCgkJDwAAAA==.Kurno:BAAALgADCgcJEwAAAA==.Kuromie:BAAALgADCgIJAgABLgAECgkJDAAGAAAAAA==.',
Ky='Kyboom:BAAALgADCgYJBgAAAA==.',
['Kà']='Kàlluu:BAAALgAECgEJAgAAAA==.',
['Kñ']='Kñightboat:BAAALgAECgYJEgAAAA==.',
La='Ladeiene:BAAALgAECgIJAgAAAA==.Laelwyn:BAAALgAECgQJCQAAAA==.Laelynd:BAAALgADCgYJBgAAAA==.Lardna:BAAALgAECgEJAQAAAA==.',
Le='Leathermommy:BAAALgAECgYJEQAAAA==.Leges:BAABLgAECn8aAAIIAAYJrSOhEgAPAgAIAAYJrSOhEgAPAgAAAA==.Lehong:BAABLgAECn8fAAMZAAgJ5xoNBwAoAgAZAAgJ5xoNBwAoAgAXAAEJWgfRgwAsAAAAAA==.Lejion:BAAALgAFFAEJAQAAAA==.Lethariel:BAAALgAECgUJBwAAAA==.Lethas:BAABLgAECn8UAAITAAgJIRqEFAAVAgATAAgJIRqEFAAVAgAAAA==.',
Li='Liandrys:BAAALgAECgEJAgAAAA==.Lightrising:BAAALgAECgIJBAAAAA==.Lilfreya:BAAALgADCgQJBAAAAA==.Lilmonstrman:BAABLgAECn8hAAMbAAgJWBRMKADEAQAbAAgJWBRMKADEAQAaAAYJzhHQCABjAQAAAA==.Limbbiscuit:BAAALgAECgQJBAAAAA==.Linger:BAABLgAECn8VAAITAAgJ3RYbbgCtAQATAAgJ3RYbbgCtAQAAAA==.Linnet:BAAALgAECgEJAQAAAA==.Litany:BAABLgAECn8gAAIiAAgJrw50FACxAQAiAAgJrw50FACxAQAAAA==.Liya:BAABLgAECn8VAAMHAAcJIBG6CgCQAQAHAAYJthK6CgCQAQAIAAUJTgpOXgDYAAAAAA==.',
Lo='Lokith:BAAALgAECgEJAQAAAA==.Lorilai:BAAALgAECgMJBAAAAA==.Loroke:BAAALgADCgkJCwAAAA==.Lots:BAAALgAECgQJBQAAAA==.Loxx:BAAALgAECgEJAgAAAA==.',
Lu='Lucith:BAAALgADCgcJCQAAAA==.Lul:BAACLgAFFH8MAAIFAAQJuhmiBQBnAQAFAAQJuhmiBQBnAQAuAAQKfyMAAwUABwmhI28QAM4CAAUABwmZI28QAM4CABgABgltHb4KAPgBAAAA.Lumpthumb:BAAALgADCgMJAwAAAA==.Lunaaru:BAAALgAECgMJAwABLgAECggJIQAEAFsgAA==.Lunamay:BAABLgAECn8hAAMEAAgJWyB2DwC9AgAEAAgJWyB2DwC9AgADAAQJSA7yLgCdAAAAAA==.',
['Lð']='Lðvergirl:BAAALgAECgIJAgAAAA==.',
['Lò']='Lòck:BAAALgAECgEJAQAAAA==.',
['Ló']='Lóki:BAAALgADCgEJAQAAAA==.',
Ma='Machotaco:BAAALgADCgMJAwAAAA==.Maddieketh:BAAALgADCgMJAwAAAA==.Maeghor:BAABLgAECn8bAAIbAAcJWReIhQDGAQAbAAcJWReIhQDGAQAAAA==.Maelleam:BAAALgAECgQJBAAAAA==.Maelsham:BAAALgADCgcJBwAAAA==.Magicash:BAAALgAECgQJDAAAAA==.Magistella:BAAALgAECgYJBgAAAA==.Magmadh:BAAALgAECgEJAgAAAA==.Malignantt:BAABLgAECn8ZAAIeAAcJBg3PEgDyAAAeAAcJBg3PEgDyAAAAAA==.Manastress:BAAALgAECgQJBQAAAA==.Mapletoast:BAAALgADCgQJBAAAAA==.Maskerade:BAAALgADCgUJBQAAAA==.Maurphious:BAAALgADCgkJJgAAAA==.Mavraela:BAAALgADCgUJDQAAAA==.',
Me='Meenhoe:BAAALgADCgUJBQAAAA==.Melee:BAAALgADCgcJBwAAAA==.Meleena:BAAALgADCgEJAQAAAA==.Melinola:BAAALgAECgMJAwAAAA==.Mellecarde:BAAALgADCgQJBAAAAA==.Melodrama:BAAALgAECgIJAwAAAA==.Messadin:BAABLgAECn8ZAAIlAAcJ7hbECwBFAQAlAAcJ7hbECwBFAQAAAA==.Metalguard:BAAALgADCgUJBQAAAA==.Metri:BAAALgAECgUJDgAAAA==.',
Mi='Michelleyeoh:BAAALgADCgUJBQABLgAECgYJDAAGAAAAAA==.Michelney:BAAALgAECgUJBQAAAA==.Mikearoni:BAABLgAECn8fAAMQAAgJRxOTDgCiAQAQAAgJRxOTDgCiAQAmAAEJeAHvTQAkAAAAAA==.Mirgaree:BAABLgAECn8UAAITAAYJoBKTRwAoAQATAAYJoBKTRwAoAQAAAA==.Mistweaving:BAACLgAFFH8RAAIWAAUJLiXQAQAbAgAWAAUJLiXQAQAbAgAuAAQKfyMAAxYACAlMI0wGAPoCABYACAlMI0wGAPoCABcABAnNFQ9MAOIAAAAA.',
Mo='Moistweaver:BAABLgAECn8dAAIWAAgJahtaFgAQAgAWAAgJahtaFgAQAgAAAA==.Mommystrasza:BAAALgAECgQJBwAAAA==.Monkfall:BAAALgADCgMJAwABLgAECgkJFgAeAAobAA==.Monkoreo:BAAALgADCgQJBAAAAA==.Monkwrld:BAABLgAECn8dAAIXAAgJZB12EAB5AgAXAAgJZB12EAB5AgAAAA==.Monty:BAAALgAECgYJBwAAAA==.Moosemode:BAAALgADCgcJBwAAAA==.Mordet:BAAALgADCgUJBQABLgAECgcJEwAGAAAAAQ==.Moridane:BAAALgAECgEJAwABLgAECgcJEwAGAAAAAQ==.',
Mu='Muffinz:BAABLgAECn8XAAIZAAYJQxMtIQD5AAAZAAYJQxMtIQD5AAAAAA==.',
My='Myau:BAABLgAECn8XAAIjAAcJKhbBDwCQAQAjAAcJKhbBDwCQAQAAAA==.Myera:BAAALgADCgUJBQAAAA==.Mynia:BAABLgAECn8hAAIBAAgJ8BALCQDRAQABAAgJ8BALCQDRAQAAAA==.Mythrius:BAAALgAECgUJCwAAAA==.',
['Mø']='Mørdu:BAAALgAECgQJCAAAAA==.',
Na='Nada:BAAALgAECgQJBQAAAA==.Nano:BAABLgAECn8ZAAIIAAcJHxhDHgC/AQAIAAcJHxhDHgC/AQAAAA==.Nardor:BAAALgAECgYJDgAAAA==.Naturelle:BAABLgAECn8WAAMEAAYJPQXcSQCpAAAEAAYJPQXcSQCpAAADAAIJFwE8igAlAAAAAA==.Nautilius:BAAALgADCggJDwAAAA==.Navaani:BAABLgAECn8dAAIlAAcJtR82BAAMAgAlAAcJtR82BAAMAgAAAA==.Nazdreg:BAACLgAFFH8GAAIIAAMJAQwCOgCfAAAIAAMJAQwCOgCfAAAuAAQKfx0AAwgABwmNHY4zAD4CAAgABwmNHY4zAD4CAAkAAQkAAHiBAAYAAAAA.Nazgull:BAAALgAECgIJAgAAAA==.',
Ne='Neisa:BAAALgADCgMJAwAAAA==.Nemesicc:BAAALgAECgUJDQAAAA==.Neotoldir:BAABLgAECn8eAAMeAAcJQR2ZBAD3AQAeAAcJQR2ZBAD3AQAnAAYJwhVPBwCMAQAAAA==.Nerfdisc:BAAALgAECgYJCQAAAA==.Nerfdruids:BAAALgADCgUJBQAAAA==.Nerozond:BAAALgAECgEJAgAAAA==.Netalli:BAABLgAECn8UAAIbAAgJmyB1JwDUAgAbAAgJmyB1JwDUAgABLgABCgQJBAAGAAAAAA==.Nevershocked:BAAALgAECggJEgAAAA==.Nezziee:BAAALgAECggJDAAAAA==.',
Ni='Nibroc:BAAALgAECgYJCgAAAA==.Nidhoggy:BAABLgAECn8VAAMVAAYJZBvmMwC0AQAVAAYJZBvmMwC0AQAUAAIJ0AUXgQBDAAAAAA==.Nife:BAAALgAECgEJAQAAAA==.',
No='Nordie:BAAALgAECgcJEwAAAA==.Noriss:BAAALgAECgEJAQABLgAECgcJEwAGAAAAAQ==.Northik:BAABLgAECn8iAAMTAAgJXiBYHwDFAgATAAgJXiBYHwDFAgAeAAYJ4Q1mEgD4AAAAAA==.Notintheface:BAAALgAECgYJEAAAAA==.',
Nu='Numlock:BAAALgAECgYJCQAAAA==.',
Ny='Nydav:BAABLgAECn8cAAIXAAgJqh42BgAsAgAXAAgJqh42BgAsAgAAAA==.Nystallina:BAAALgADCgMJAwAAAA==.',
['Ní']='Níítefall:BAABLgAECn8bAAIRAAcJ4CB3AwCbAgARAAcJ4CB3AwCbAgABLgAECggJFQAbAGgZAA==.',
Oa='Oakbreaker:BAAALgAECgEJAQABLgAFFAMJBQAhAOEMAA==.',
Ob='Obalma:BAAALgAECgUJCAAAAA==.',
Od='Odrade:BAAALgADCgIJAgAAAA==.Odwalla:BAACLgAFFH8LAAIMAAQJix4OBACDAQAMAAQJix4OBACDAQAuAAQKfyMABAwACAlQIw0KAPgCAAwACAlQIw0KAPgCAAEABgmtHysVAHUBAAIAAwkMFDdkAK8AAAAA.',
Oh='Ohgodno:BAAALgAECgcJDwAAAA==.',
Ok='Oktal:BAAALgAECgYJBgAAAA==.',
Ol='Olmec:BAABLgAECn8eAAIUAAgJUxL+EACbAQAUAAgJUxL+EACbAQAAAA==.',
On='Onlydesert:BAAALgAECgYJCwAAAA==.',
Oo='Oorudun:BAAALgADCgYJBgAAAA==.',
Op='Ophiel:BAAALgAECgUJCQAAAA==.Optiks:BAABLgAECn8UAAIbAAcJ0xa+MAChAQAbAAcJ0xa+MAChAQAAAA==.',
Or='Orblio:BAAALgADCgQJBAAAAA==.Orcofhell:BAAALgADCgkJDwAAAA==.Orcthas:BAAALgAECgMJBQAAAA==.Orksauce:BAACLgAFFH8FAAIhAAMJ4QwZDwD8AAAhAAMJ4QwZDwD8AAAuAAQKfyEAAyEACAn7IdYBALgCACEACAn7IdYBALgCACAAAQnZFggcAEgAAAAA.Orleron:BAAALgADCgkJDAAAAA==.Oroth:BAAALgAECgYJDwAAAA==.',
Os='Osares:BAAALgAECgUJCAAAAA==.Oshizitskoro:BAAALgAECgEJAQAAAA==.',
Ot='Otsu:BAAALgADCgMJAwABLgAECgYJDgAGAAAAAA==.',
Ou='Outofwater:BAAALgADCgYJBgAAAA==.Outtyfox:BAAALgADCgIJAgAAAA==.',
['Oß']='Oß:BAAALgAECgYJCgABLgAECggJJgAXALkQAA==.',
Pa='Pagophobia:BAAALgADCgEJAQAAAA==.Pakku:BAABLgAECn8UAAIbAAgJ5RHIKQC9AQAbAAgJ5RHIKQC9AQAAAA==.Palilicious:BAAALgAECgEJAQAAAA==.Pallytree:BAAALgAECgUJBwAAAA==.Pantheeon:BAAALgADCgIJAgAAAA==.Parzival:BAABLgAECn8YAAIbAAcJLgt/SgBPAQAbAAcJLgt/SgBPAQAAAA==.Patchface:BAAALgADCgcJBwAAAA==.',
Pd='Pdp:BAABLgAECn8VAAIDAAcJiCO3FgBXAgADAAcJiCO3FgBXAgAAAA==.',
Pe='Perkbane:BAABLgAECn8UAAQHAAgJohtdEAAoAQAHAAQJZh9dEAAoAQAIAAcJtxPzXgDWAAAJAAIJnQ/STgCBAAAAAA==.Perkdragon:BAAALgAECgYJBQABLgAECggJFAAHAKIbAA==.Perkyl:BAAALgAECgYJDAAAAA==.Petrol:BAAALgAECgYJBwAAAA==.',
Ph='Phage:BAAALgAECgEJAgABLgAECgYJEwAGAAAAAA==.Pheel:BAAALgAECgUJBQAAAA==.Phillactery:BAAALgAECgMJAwAAAA==.Phlykz:BAAALgADCgEJAQAAAA==.Phosho:BAAALgADCgYJBgAAAA==.',
Pi='Pig:BAAALgAECgQJBAAAAA==.Pikevarr:BAAALgAECgYJCQAAAA==.',
Pk='Pkrage:BAABLgAECn8mAAMkAAkJfxjnCwBOAgAkAAkJfxjnCwBOAgAFAAEJTAA4twAIAAAAAA==.',
Pl='Plagueborne:BAAALgAECggJDgAAAA==.Plazzy:BAABLgAECn8mAAQhAAkJnBuQDwCsAgAhAAkJ7BmQDwCsAgAgAAYJYBcpBQB2AQAoAAEJMw//DABCAAAAAA==.Plopp:BAEALgAECgYJEQAAAA==.',
Po='Pollywog:BAAALgADCgYJBgABLgAFFAUJEQAWAC4lAA==.Polyethylene:BAAALgAECgYJEAAAAA==.Popprocks:BAAALgADCgEJAQAAAA==.',
Pr='Pretzel:BAAALgAECgEJAwABLgAECgcJEwAGAAAAAQ==.Proxymate:BAAALgADCgMJAwAAAA==.',
Pu='Puhtty:BAAALgAECgMJAwAAAA==.Punkfangs:BAAALgADCgcJFAAAAA==.',
['Pë']='Pëaches:BAAALgADCgcJBwABLgAFFAUJDQAKABELAA==.',
['Pï']='Pï:BAAALgAECgQJBgAAAA==.',
Qk='Qkoira:BAAALgADCgYJBgABLgADCgcJCgAGAAAAAA==.',
Qu='Quanlain:BAABLgAECn8XAAMMAAgJQBmUEQAHAgAMAAgJQBmUEQAHAgACAAMJmBV0ZgClAAAAAA==.Quasár:BAAALgAECgYJCgAAAA==.Quilara:BAAALgADCgkJHQAAAA==.Quillathe:BAABLgAECn8dAAMOAAgJvRPkBwAdAgAOAAgJvRPkBwAdAgAjAAEJbQYoZQAuAAAAAA==.',
Ra='Radíant:BAAALgADCgUJBQABLgABCgYJBgAGAAAAAA==.Ragemaster:BAAALgAECgQJCQAAAA==.Ramiusraven:BAAALgADCgIJAgAAAA==.Rancore:BAABLgAECn8aAAMFAAgJ9RZ2DQDbAQAFAAgJ9RZ2DQDbAQAYAAMJcgqeKwCXAAAAAA==.Rashdar:BAACLgAFFH8GAAILAAMJdAXIJADcAAALAAMJdAXIJADcAAAuAAQKfxcAAgsACAmHFopDABoCAAsACAmHFopDABoCAAAA.Rattpack:BAABLgAECn8XAAMSAAcJng7yOAAfAQASAAUJ4xLyOAAfAQAKAAUJXArjSwDCAAAAAA==.Raves:BAABLgAECn8ZAAIbAAYJUiDkVwAxAgAbAAYJUiDkVwAxAgAAAA==.',
Re='Regilz:BAAALgAECgYJCwAAAA==.Reselience:BAAALgAECgQJBAABLgAECggJHAAIAIogAA==.Rewara:BAAALgADCgcJBwAAAA==.',
Rh='Rhadamenth:BAAALgADCgMJAwAAAA==.Rhinity:BAAALgADCgQJBAABLgAECgYJEwAGAAAAAA==.Rhyolite:BAAALgAECgEJAQAAAA==.',
Ri='Riaeviana:BAAALgAECgYJDwAAAA==.Ribeyye:BAAALgAECgYJCAAAAA==.Rigormistis:BAAALgADCgEJAQAAAA==.Rilde:BAAALgADCgcJBwAAAA==.Rinjielune:BAAALgADCgYJDwAAAA==.Risch:BAAALgAECgMJAwAAAA==.Rius:BAAALgADCgIJAgAAAA==.',
Ro='Roberts:BAAALgADCgkJEAAAAA==.Robroÿ:BAAALgAECgYJDgAAAA==.Robrõy:BAAALgAECgkJBQABLgAECgkJCAAGAAAAAA==.Roku:BAAALgAFFAIJAgABLgAFFAYJGwAIAJwfAA==.Romex:BAAALgADCgEJAQAAAA==.Rondo:BAAALgADCgUJBQAAAA==.Roseclaw:BAEALgAECgYJBgABLgAECgYJCwAGAAAAAA==.Roseclawed:BAEALgAECgYJCwAAAA==.Roxso:BAACLgAFFH8ZAAIbAAYJMyLCAgANAgAbAAYJMyLCAgANAgAuAAQKfx4AAhsACQmJJKICANQDABsACQmJJKICANQDAAAA.',
Ru='Runnigan:BAAALgADCgQJBAAAAA==.',
Rx='Rxse:BAAALgAECgYJCgAAAA==.',
Ry='Rylun:BAAALgADCgYJCQAAAA==.',
['Rà']='Rànik:BAAALgADCgIJAgAAAA==.',
['Rë']='Rëdmagma:BAABLgAECn8YAAIUAAgJ8xRDEQCXAQAUAAgJ8xRDEQCXAQAAAA==.',
Sa='Saasaki:BAAALgAECgYJDgAAAA==.Sabrinacarp:BAABLgAECn8hAAIiAAgJNhmQDAAOAgAiAAgJNhmQDAAOAgAAAA==.Sabryelle:BAAALgADCgEJAgAAAA==.Sacrelicious:BAABLgAECn8UAAILAAYJEA8ESgAsAQALAAYJEA8ESgAsAQAAAA==.Sagewynn:BAAALgAECgYJCgAAAA==.Salfroc:BAABLgAECn8iAAMHAAgJPRZ4AQAAAgAHAAgJPRZ4AQAAAgAJAAIJ5Qr1HgA+AAAAAA==.Saltychief:BAAALgADCgUJBwAAAA==.Saplo:BAABLgAECn8eAAIMAAgJ5gr/JACGAQAMAAgJ5gr/JACGAQAAAA==.Sapphiraflux:BAAALgADCgIJAgAAAA==.Sarif:BAAALgADCgcJDAAAAA==.Sarvashi:BAAALgAECgMJBAAAAA==.Sasara:BAAALgAECgMJBgAAAA==.Sathas:BAAALgADCgQJBAAAAA==.Saxel:BAAALgAECggJEAAAAA==.',
Sc='Scrabble:BAAALgAECgIJAgAAAA==.',
Se='Segio:BAAALgAECggJDgAAAA==.Selcia:BAAALgAECgYJDQAAAA==.Serenati:BAAALgAECgcJEAAAAA==.Sermour:BAAALgAECgEJAQAAAA==.',
Sh='Shadephoenix:BAABLgAECn8ZAAInAAgJLgU3BwAEAQAnAAgJLgU3BwAEAQAAAA==.Shados:BAAALgAFFAEJAQAAAA==.Shadowen:BAAALgAECgYJCQAAAA==.Shambülance:BAAALgADCgEJAQAAAA==.Sharavia:BAABLgAECn8XAAISAAcJmQnrEQAjAQASAAcJmQnrEQAjAQAAAA==.Shari:BAABLgAECn8XAAIJAAYJdBVmBwA9AQAJAAYJdBVmBwA9AQAAAA==.Shatoo:BAAALgAECgYJDwAAAA==.Shaunchaos:BAAALgADCgMJAwAAAA==.Shaunrawr:BAABLgAECn8eAAMMAAcJHBgeIwCQAQAMAAcJHBgeIwCQAQACAAIJ5wXrewBUAAAAAA==.Shield:BAAALgADCgMJAwAAAA==.Shiftedtea:BAAALgAECgEJAQAAAA==.Shizaxe:BAAALgADCgUJBQAAAA==.Shizish:BAAALgAECgcJEwAAAA==.Shocktuah:BAABLgAECn8bAAIUAAcJHCTWBgA7AgAUAAcJHCTWBgA7AgAAAA==.Shonúff:BAABLgAECn8iAAMXAAcJJxwtCQDnAQAXAAcJJxwtCQDnAQAWAAUJUgkNRgDDAAAAAA==.Shotaro:BAABLgAECn8VAAMiAAYJdyBSCgAxAgAiAAYJdyBSCgAxAgAlAAQJlhhQHQAfAQAAAA==.',
Si='Sillybear:BAAALgAECgQJBQAAAA==.Silvermain:BAAALgADCgQJBAAAAA==.Sinful:BAABLgAECn8nAAMMAAgJMRNAIACfAQAMAAgJMRNAIACfAQACAAMJ6AAufwBJAAAAAA==.Singarti:BAAALgAECggJDgAAAA==.Sizzlesnout:BAAALgAECgMJAwAAAA==.',
Sk='Skalagrim:BAAALgADCgMJAwAAAA==.Skedu:BAAALgADCgEJAQAAAA==.Skeptyk:BAABLgAECn8YAAINAAcJiR1oBgBSAgANAAcJiR1oBgBSAgAAAA==.Skolivia:BAECLgAFFH8GAAMjAAMJCwjKDQDqAAAjAAMJCwjKDQDqAAAOAAEJ9AFXIABAAAAuAAQKfxUAAyMACAkIF2QZABYCACMACAkIF2QZABYCAA4AAglfEJpJAHEAAAAA.Skroggo:BAAALgAECgQJBgAAAA==.Skådoosh:BAABLgAECn8mAAMXAAgJuRBGEQBsAQAXAAgJuRBGEQBsAQAZAAQJtAgmawCVAAAAAA==.',
Sl='Slightdawn:BAAALgADCgkJCQAAAA==.Sloppymop:BAAALgADCgUJCAAAAA==.Sloppysteaks:BAAALgADCgUJBQAAAA==.',
Sm='Smallben:BAAALgADCgIJAgAAAA==.Smiley:BAAALgAECgYJDgAAAA==.Smite:BAAALgADCgIJAgAAAA==.Smitti:BAAALgAECgMJAwAAAA==.Smug:BAABLgAECn8kAAIKAAkJ6iTjAABHAwAKAAkJ6iTjAABHAwAAAA==.',
Sn='Snapcrklepop:BAAALgADCgUJBQAAAA==.Sniffledoo:BAABLgAECn8UAAIkAAcJXg1lDwApAQAkAAcJXg1lDwApAQAAAA==.Snuwuf:BAAALgADCgEJAQAAAA==.Snóóf:BAAALgAECgQJCQAAAA==.',
So='Solomeani:BAAALgAECgMJBAAAAA==.Sonicnoah:BAAALgAECgEJAQAAAA==.Sourfangs:BAACLgAFFH8GAAIFAAMJsx71DAAkAQAFAAMJsx71DAAkAQAuAAQKfxcAAgUACAkmJaAFAE0DAAUACAkmJaAFAE0DAAAA.Soxx:BAAALgAECgEJAQAAAA==.',
Sp='Sparklymayhm:BAAALgADCgcJCwAAAA==.Spearz:BAAALgADCgQJBAAAAA==.Speedmonster:BAAALgADCggJCAAAAA==.Spicymilk:BAABLgAECn8hAAIaAAgJoCH0AQCTAgAaAAgJoCH0AQCTAgAAAA==.Spicypeño:BAABLgAECn8bAAMPAAcJaiE7DAAXAgAPAAYJPiE7DAAXAgAQAAUJFB3XIgCnAQABLgAFFAgJFwAQAKMSAA==.Spinach:BAABLgAECn8YAAMiAAcJWhInHwBOAQAiAAYJ0BInHwBOAQALAAEJiwO65QAbAAAAAA==.Spire:BAABLgAECn8XAAQbAAYJXAakdADuAAAbAAYJXAakdADuAAAaAAIJAQLICQBNAAAcAAEJPwFCEgAVAAAAAA==.Splithoofe:BAAALgAECgUJBQABLgAFFAIJBgAMAAwIAA==.Sprawl:BAABLgAECn8lAAIoAAgJaxhnAQAbAgAoAAgJaxhnAQAbAgAAAA==.',
Sq='Squrrlydan:BAAALgAECgcJEwAAAA==.',
St='Staint:BAAALgAECgYJEwAAAA==.Starnights:BAAALgAECgcJEwAAAA==.Statman:BAABLgAECn8eAAIkAAgJ1gyVDQBGAQAkAAgJ1gyVDQBGAQAAAA==.Steelbubble:BAAALgAECgYJDwAAAA==.Stengah:BAABLgAECn8eAAImAAgJtiSXAABZAwAmAAgJtiSXAABZAwAAAA==.Steris:BAAALgADCgYJBgAAAA==.Strela:BAAALgAECggJKQAAAQ==.Stressummon:BAAALgADCgMJAgAAAA==.Strykie:BAAALgADCgQJBAAAAA==.',
Su='Sulina:BAAALgAECgQJBwAAAA==.Suzaki:BAAALgADCgkJCQAAAA==.',
Sv='Svetlian:BAAALgADCgQJBAABLgAECggJKQAGAAAAAA==.',
Sw='Swtblsphmy:BAABLgAECn8iAAIVAAgJgxC3LQDTAQAVAAgJgxC3LQDTAQAAAA==.',
Sy='Symphony:BAAALgADCgEJAQAAAA==.Syradora:BAAALgAECgYJDQAAAA==.Syynner:BAAALgAECgcJBwAAAA==.',
['Sè']='Sèd:BAAALgADCgcJDAAAAA==.',
Ta='Taelak:BAAALgAECgYJCQAAAA==.Tahrin:BAABLgAECn8dAAIMAAgJpBz2DgAhAgAMAAgJpBz2DgAhAgAAAA==.Talamon:BAABLgAECn8aAAIZAAcJYBZ7DgCmAQAZAAcJYBZ7DgCmAQAAAA==.Talmøre:BAAALgADCgMJAwAAAA==.Talyyon:BAAALgAECgYJEAAAAA==.Tandinise:BAAALgAFFAIJAgAAAA==.Tandruid:BAAALgAECgMJBgABLgAECggJHAAIAIogAA==.Tanmonk:BAAALgAECgQJBAABLgAECggJHAAIAIogAA==.Taproot:BAAALgAECgkJCQAAAA==.Tas:BAAALgADCgIJAgAAAA==.Tashi:BAABLgAECn8bAAICAAgJhBE0BQCrAQACAAgJhBE0BQCrAQAAAA==.Tasina:BAAALgAECgEJAQABLgAECgUJCAAGAAAAAA==.Tastictank:BAAALgAECgQJBgAAAA==.Taurenamos:BAABLgAECn8fAAQDAAcJfxhqGgApAQADAAYJjRhqGgApAQAEAAcJKA4/SgCoAAAfAAYJ4AYrFAB/AAAAAA==.Taynam:BAAALgAECgYJBwABLgAECgcJCwAGAAAAAA==.',
Te='Tebas:BAAALgAECgQJBQAAAA==.Teival:BAABLgAECn8fAAIMAAgJGhuGDAA7AgAMAAgJGhuGDAA7AgAAAA==.Tempëst:BAAALgADCgIJAgAAAA==.Tenchu:BAAALgAECgYJDwAAAA==.Tenfour:BAAALgADCgYJBgAAAA==.Tenseven:BAAALgAECgYJDwAAAA==.Teredorn:BAAALgADCgkJCgABLgAECgkJHQAiAMwbAA==.Terrorbláde:BAAALgADCgcJBwAAAA==.Terrørßlade:BAAALgADCgYJBgAAAA==.',
Th='Thalion:BAAALgAECgcJBwAAAA==.Thark:BAAALgAECgUJBgABLgAECgcJGgASAMAlAA==.Therris:BAABLgAECn8ZAAIMAAcJCA1tLwBTAQAMAAcJCA1tLwBTAQAAAA==.Thideaes:BAAALgADCgYJBQAAAA==.Thidias:BAAALgAECgIJAgAAAA==.Thorimane:BAAALgAECgQJAwABLgAECgcJEwAGAAAAAA==.Thrizzowd:BAAALgADCgkJDQAAAA==.Throwd:BAABLgAECn8iAAIhAAgJThHSCgC8AQAhAAgJThHSCgC8AQAAAA==.Thwark:BAAALgADCgQJBAABLgAECgcJGgASAMAlAA==.',
Ti='Tinytony:BAABLgAECn8iAAMlAAkJrBPzCAB+AQAlAAcJ+BfzCAB+AQALAAcJRQrVTgAgAQAAAA==.',
To='Toranis:BAAALgAECgEJAQAAAA==.Torrellan:BAAALgADCgMJAwAAAA==.Torrents:BAABLgAECn8jAAQVAAgJZSO7AQAeAwAVAAgJZSO7AQAeAwAUAAUJZhKDMgCvAAApAAIJAQcxJwBnAAAAAA==.Touchofchaos:BAAALgADCgYJBQAAAA==.Toxíc:BAAALgADCgcJEgAAAA==.',
Tr='Traffyfu:BAAALgAECgMJAwAAAA==.Trailerpark:BAAALgAECgMJAQAAAA==.Traver:BAAALgAECgQJBAAAAA==.Trinytee:BAAALgAECgEJAQAAAA==.Trogdor:BAAALgADCgQJBAAAAA==.',
Tu='Ture:BAAALgADCgkJGQAAAA==.Turnandburn:BAAALgAECgEJAQAAAA==.',
Tw='Twistedsugar:BAAALgAECgMJAwAAAA==.Twìztid:BAABLgAECn8dAAIKAAgJniPnBACWAgAKAAgJniPnBACWAgAAAA==.',
Ty='Tyriäel:BAABLgAECn8nAAIeAAkJDx9CAQCIAgAeAAkJDx9CAQCIAgAAAA==.Tyrrible:BAAALgADCggJDwAAAA==.',
['Tà']='Tàyla:BAAALgADCgYJBgABLgAECgEJAQAGAAAAAA==.',
['Tð']='Tðxîc:BAAALgAECgEJAgAAAA==.',
Ul='Ulther:BAAALgAECgYJCQAAAA==.Ultìmecia:BAAALgAECgYJAQAAAA==.',
Un='Unbinddeath:BAAALgADCgQJBwAAAA==.Unfriendly:BAAALgADCgEJAQAAAA==.',
Up='Upside:BAAALgAECgYJDAAAAA==.',
Ur='Uruz:BAABLgAECn8bAAIFAAgJ3h9TGQCBAgAFAAgJ3h9TGQCBAgAAAA==.',
Ut='Uthêr:BAAALgADCgMJAwAAAA==.',
Va='Vacare:BAAALgAECgYJCQAAAA==.Valdyria:BAAALgADCgQJBwAAAA==.Valefar:BAAALgAECgMJAwAAAA==.Valkoienne:BAAALgAECgEJAQAAAA==.Valyniss:BAAALgAECgEJAgAAAA==.Vamp:BAAALgADCgUJBQAAAA==.Vanart:BAAALgAECgkJBQAAAA==.Vandemar:BAAALgAECgMJAwAAAA==.Vanderpump:BAAALgADCgYJBgABLgAECgQJBAAGAAAAAA==.Vanreu:BAAALgAECgYJBwAAAA==.Vavictus:BAAALgAECgYJCQAAAA==.',
Ve='Vedronorael:BAAALgADCgkJFgAAAA==.Vekkar:BAAALgAECgEJAQAAAA==.Velanthia:BAAALgAECgEJAQAAAA==.Vengrath:BAABLgAECn8YAAIbAAgJPiKoCgCVAgAbAAgJPiKoCgCVAgAAAA==.Venomgodd:BAAALgADCgEJAQAAAA==.Verderben:BAAALgAECgYJCgAAAA==.',
Vi='Vibestotem:BAAALgAECgEJAQAAAA==.Vilenia:BAAALgAECgcJEwAAAA==.Vilkasdk:BAAALgAECgYJCQAAAA==.Vinchenzo:BAAALgAECgEJAQAAAA==.Vinhelsin:BAAALgAECgQJBAAAAA==.Violetangel:BAAALgAECgYJBQAAAA==.Vionir:BAABLgAECn8bAAIBAAgJASOyBAA3AgABAAgJASOyBAA3AgAAAA==.Vitality:BAAALgAECgIJAgAAAA==.',
Vo='Voidrush:BAAALgAECgYJCQAAAA==.Voirdire:BAAALgAECgcJEAAAAA==.Voron:BAAALgAECgYJCwAAAA==.',
Vu='Vulpa:BAABLgAECn8mAAMJAAgJCQ+/BgBLAQAJAAgJCQ+/BgBLAQAIAAIJFAJ7DwE/AAAAAA==.',
Vy='Vynessa:BAAALgADCgkJFAAAAA==.Vyshareth:BAAALgADCgcJBwAAAA==.',
Wa='Wanren:BAAALgAECgQJBAAAAA==.Wargodd:BAAALgADCgMJAwAAAA==.Waterwhip:BAABLgAFFH8FAAIVAAIJSwo8HACFAAAVAAIJSwo8HACFAAAAAA==.',
We='Westfall:BAABLgAECn8WAAMeAAkJChsaDQA+AgAeAAkJChsaDQA+AgATAAEJkwEaOQEfAAAAAA==.',
Wh='Whirl:BAAALgAECgQJCwABLgAECgcJHQAFAGgaAA==.Whirlock:BAAALgADCgYJBgAAAA==.Whirlwind:BAABLgAECn8dAAIFAAcJaBpFKgAQAgAFAAcJaBpFKgAQAgAAAA==.Whydoiexist:BAABLgAECn8VAAIZAAYJHCAFHQAbAgAZAAYJHCAFHQAbAgAAAA==.',
Wi='Willrun:BAAALgAECgUJEAAAAA==.Windwatcher:BAABLgAECn8XAAIUAAYJEgaAKwDUAAAUAAYJEgaAKwDUAAAAAA==.Witheredyam:BAAALgADCgYJBgAAAA==.Withirony:BAAALgAECgIJAgAAAA==.',
Wo='Wompeal:BAABLgAECn8fAAINAAgJXR64CADAAgANAAgJXR64CADAAgAAAA==.Wonkwonk:BAABLgAECn8UAAIbAAcJ2gM0ewDeAAAbAAcJ2gM0ewDeAAAAAA==.Worth:BAABLgAECn8aAAILAAcJhCSrCgB4AgALAAcJhCSrCgB4AgAAAA==.',
Wr='Wrathofdirt:BAAALgADCgUJBQAAAA==.Wravin:BAABLgAECn8nAAIMAAkJ1g5oGgDCAQAMAAkJ1g5oGgDCAQABLgAECgkJJwANAJsNAA==.Wrukolas:BAAALgAECgYJEQAAAA==.',
Wu='Wulf:BAAALgAECgEJAQAAAA==.Wumdaorm:BAAALgADCgEJAQAAAA==.',
Wy='Wyhm:BAAALgADCgUJBwAAAA==.Wystan:BAABLgAECn8jAAIVAAgJ4hgBDQAcAgAVAAgJ4hgBDQAcAgAAAA==.',
['Wé']='Wés:BAABLgAECn8hAAIZAAgJ1BmCBwAfAgAZAAgJ1BmCBwAfAgAAAA==.',
['Wí']='Wíckedwítch:BAAALgAECgcJCQAAAA==.',
Xa='Xalatoes:BAAALgADCgEJAwAAAA==.Xanden:BAAALgADCgcJCAAAAA==.Xanthe:BAABLgAECn8YAAMiAAcJmAc9JQAeAQAiAAcJmAc9JQAeAQALAAEJIwQdWAEnAAAAAA==.Xayden:BAAALgADCgMJAwAAAA==.',
Xe='Xeal:BAAALgAECgYJEQAAAA==.Xelkath:BAAALgAECgYJEQAAAA==.Xenomorphic:BAACLgAFFH8MAAIWAAQJ1xroCQA+AQAWAAQJ1xroCQA+AQAuAAQKfx8AAhYACQkXIgcBAFgDABYACQkXIgcBAFgDAAAA.Xentow:BAABLgAECn8ZAAIMAAcJ4AnjPAAgAQAMAAcJ4AnjPAAgAQAAAA==.',
Xu='Xuanfeng:BAAALgAECgYJEQAAAA==.',
Xy='Xythros:BAAALgADCggJCAAAAA==.',
Ya='Yacob:BAAALgADCgEJAgABLgAECggJEQAGAAAAAA==.Yamling:BAAALgADCgkJHQAAAA==.Yarel:BAACLgAFFH8JAAIWAAUJxwdQBgBjAQAWAAUJxwdQBgBjAQAuAAQKfyoAAxYACQmhHtoNAHgCABYACQmhHtoNAHgCABcACQldGYQLAL0BAAEuAAUUAgkCAAYAAAAA.Yayaka:BAAALgAECgYJDgAAAA==.',
Yi='Yizdano:BAABLgAECn8eAAMhAAgJTxm6BgAKAgAhAAgJTxm6BgAKAgAgAAEJaxRtHQBAAAAAAA==.',
Yo='Yoloscrap:BAAALgADCgYJBQAAAA==.',
Yu='Yukiina:BAAALgAECgMJAwAAAA==.',
['Yù']='Yùm:BAAALgAECgcJDAAAAA==.',
Za='Zaccheus:BAAALgAECgYJEAAAAA==.Zalruin:BAAALgADCgkJCgAAAA==.Zambora:BAAALgADCgkJFQAAAA==.Zarb:BAAALgADCggJCAAAAA==.',
Ze='Zeebra:BAAALgAECgUJDwAAAA==.Zeenii:BAAALgADCgMJAwAAAA==.Zeesaw:BAABLgAECn8dAAMFAAcJbx2xFgB9AQAFAAcJcByxFgB9AQAYAAYJwhGcDQAqAQAAAA==.Zeretrix:BAABLgAECn8nAAIbAAkJzxzNCQChAgAbAAkJzxzNCQChAgAAAA==.Zeroperfect:BAAALgADCgUJBQAAAA==.',
Zi='Zikà:BAAALgADCgMJAwAAAA==.Zinni:BAAALgADCgIJAgAAAA==.Ziros:BAAALgAECgYJBQAAAA==.',
Zl='Zlutar:BAAALgAECgMJBQAAAA==.',
Zo='Zonotix:BAAALgAECgMJAwAAAA==.',
Zy='Zynos:BAABLgAECn8bAAIKAAgJAAyUOAABAQAKAAgJAAyUOAABAQAAAA==.',
['Ãl']='Ãlexstrasza:BAAALgADCgUJAwAAAA==.',
['Ça']='Çalindrel:BAAALgADCgkJCQAAAA==.',
['Ñu']='Ñuk:BAAALgAECgUJCQAAAA==.',
['Úà']='Úà:BAAALgADCgcJCgAAAA==.',
['Üb']='Überhealz:BAAALgAECgMJAwABLgAECgYJEAAGAAAAAA==.',
['ßö']='ßöw:BAABLgAECn8gAAMMAAgJFRIqGQDLAQAMAAgJFRIqGQDLAQACAAYJZghZWQDfAAAAAA==.',
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
