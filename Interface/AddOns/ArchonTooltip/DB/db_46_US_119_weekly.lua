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

local lookup = {'Hunter-Survival','Hunter-Marksmanship','Druid-Balance','Druid-Restoration','Warrior-Fury','Unknown-Unknown','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Priest-Discipline','DemonHunter-Devourer','Paladin-Retribution','Hunter-BeastMastery','Priest-Holy','DemonHunter-Vengeance','DemonHunter-Havoc','Shaman-Restoration','Monk-Mistweaver','Monk-Windwalker','Mage-Arcane','Mage-Frost','Mage-Fire','Druid-Feral','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Arms','Rogue-Assassination','Rogue-Subtlety','Monk-Brewmaster','Paladin-Holy','Evoker-Augmentation','Evoker-Devastation','Warrior-Protection','Evoker-Preservation','Paladin-Protection','DeathKnight-Frost','Shaman-Elemental','Priest-Shadow','Rogue-Outlaw','Druid-Guardian','Shaman-Enhancement',}
local provider = {region='US',realm='Hellscream',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aarix:BAABLgAECn8dAAMBAAgJwwsIBACxAQABAAgJwwsIBACxAQACAAEJCgCwnAACAAAAAA==.',
Ad='Adaptabull:BAABLgAECn8UAAMDAAcJGhqTIQDwAQADAAcJGhqTIQDwAQAEAAIJIxWqrgBoAAAAAA==.Adari:BAAALgADCgMJAwAAAA==.Adune:BAAALgADCgQJBAAAAA==.',
Ae='Aelinessa:BAAALgAECgUJCQAAAA==.Aeo:BAAALgAECgYJDAABLgAECggJGwAEAN0fAA==.',
Ai='Aiel:BAAALgAECgYJDAABLgAECgcJGQAFALAZAA==.',
Al='Albedò:BAAALgAECgEJAQAAAA==.Aldrîch:BAAALgADCgMJAwAAAA==.Allyra:BAAALgADCgIJAgABLgAECgIJBQAGAAAAAA==.Allzaz:BAAALgAECgQJCAABLgAECgcJFAAHAPcTAA==.Allzera:BAABLgAECn8UAAQHAAcJ9xO/DgBEAQAHAAUJOhC/DgBEAQAIAAUJeRIciwBDAQAJAAMJggejUgB2AAAAAA==.Alric:BAAALgAECgYJDAAAAA==.',
Am='Amalei:BAAALgADCgYJBgAAAA==.Amberness:BAAALgAECgIJAgABLgAFFAEJAQAGAAAAAA==.Ammaria:BAAALgADCgUJBQAAAA==.Amorose:BAAALgAECgcJCAAAAA==.',
An='Anastassia:BAAALgADCggJCAABLgAECgkJGQAKAJsGAA==.Andol:BAAALgADCgUJBQABLgAECgYJEAAGAAAAAA==.Anduwyn:BAAALgADCgIJAgAAAA==.Anezra:BAAALgAECgEJAQAAAA==.Angelmack:BAAALgAECggJBgAAAA==.Anibella:BAABLgAECn8WAAILAAgJWRt3KABhAgALAAgJWRt3KABhAgAAAA==.Antons:BAAALgADCgkJEAAAAA==.Anuke:BAAALgAECgQJBwAAAA==.',
Ap='Aphlykted:BAAALgADCgYJBgAAAA==.',
Ar='Arbinu:BAAALgADCgMJAwAAAA==.Arflane:BAAALgADCgEJAQAAAA==.Argenta:BAAALgADCgEJAQAAAA==.Arkhlight:BAABLgAECn8WAAIMAAgJ8hy1BgAkAgAMAAgJ8hy1BgAkAgAAAA==.Arkillos:BAAALgAECgEJAQAAAA==.Armerous:BAAALgADCgMJAwAAAA==.Arnlok:BAAALgADCgMJAwAAAA==.Arrowhoof:BAABLgAFFH8FAAINAAIJwwXhGgCZAAANAAIJwwXhGgCZAAAAAA==.Arthurian:BAAALgADCgUJEQAAAA==.',
As='Ashmorph:BAAALgADCgYJCAAAAA==.Ashpriest:BAABLgAECn8WAAMOAAgJjRnrJQC7AQAOAAgJLRnrJQC7AQAKAAMJzxlIDQDmAAAAAA==.Ashýra:BAABLgAECn8eAAIOAAgJUA62BwCMAQAOAAgJUA62BwCMAQAAAA==.Asphyxxed:BAAALgAECgEJAQAAAA==.Asterisk:BAABLgAECn8gAAINAAgJFRdiCQDSAQANAAgJFRdiCQDSAQAAAA==.Asya:BAAALgAECgYJBQAAAA==.',
At='Ataxica:BAAALgAECgEJAQAAAA==.Atlas:BAAALgAECgMJAwAAAA==.Attanu:BAAALgADCgIJAgAAAA==.Attilathepun:BAAALgADCgcJBwAAAA==.',
Au='Augrizia:BAAALgADCgMJBQAAAA==.Auriêl:BAAALgADCgcJEQAAAA==.',
Az='Azastra:BAAALgAECgYJEAAAAA==.Azer:BAAALgADCgYJBgAAAA==.',
['Añ']='Aña:BAABLgAECn8VAAQPAAYJfCTFAQDDAQAPAAYJfCTFAQDDAQAQAAIJ1BTaWQB8AAALAAEJfwu15gArAAAAAA==.Añarchist:BAAALgADCggJFQABLgAECgYJFQAPAHwkAA==.',
Ba='Baelzharon:BAAALgAECgYJDQAAAA==.Baern:BAAALgAECgYJDwABLgAECggJBwAGAAAAAA==.Bagelpanda:BAAALgADCgMJAwAAAA==.Balròg:BAAALgADCgEJAQAAAA==.Barrthas:BAAALgAFFAIJAwABLgABCgQJBAAGAAAAAA==.Basalt:BAABLgAECn8WAAINAAgJyxbJCwCvAQANAAgJyxbJCwCvAQAAAA==.Bastenwode:BAAALgAECgMJBQAAAA==.',
Bb='Bbye:BAAALgAECgEJAQAAAA==.',
Be='Bearmyload:BAAALgADCgUJBQABLgAECgcJCwAGAAAAAA==.Beastwrld:BAAALgADCgcJGgAAAA==.Becký:BAABLgAECn8VAAINAAYJ2R0ADwCLAQANAAYJ2R0ADwCLAQAAAA==.Beeflomein:BAAALgADCgEJAQAAAA==.Beroan:BAAALgADCgYJBgAAAA==.',
Bi='Bigcøøkie:BAAALgADCgYJBgAAAA==.Bighealin:BAAALgAECgQJBAAAAA==.Bigjim:BAAALgAECggJEQAAAA==.Biglul:BAAALgAECgMJAwABLgAFFAMJCgAFAPIeAA==.Bigolcrities:BAAALgADCgEJAQAAAA==.Bivivi:BAAALgAECgMJAwAAAA==.',
Bj='Bjorn:BAAALgADCgQJBAAAAA==.',
Bl='Blackmagma:BAAALgADCgkJBwABLgAECggJEQAGAAAAAA==.Blackpiink:BAAALgAECgUJCgAAAA==.Blackppink:BAACLgAFFH8GAAIRAAMJbQ4KCADUAAARAAMJbQ4KCADUAAAuAAQKfx4AAhEACQmYG4gLAMYCABEACQmYG4gLAMYCAAAA.Blackppinkk:BAAALgAECgIJBAAAAA==.Bladefi:BAABLgAECn8YAAMQAAYJECUyAwDIAQALAAYJnB1oPgD7AQAQAAUJWyYyAwDIAQAAAA==.Blamo:BAABLgAECn8WAAIEAAgJTBI5CgC1AQAEAAgJTBI5CgC1AQAAAA==.Blesedtogoon:BAAALgAECgMJBAAAAA==.Bloodbunny:BAAALgAECgMJAwAAAA==.Bluddbeard:BAAALgAECgcJBgAAAA==.',
Bm='Bmoneycuh:BAABLgAECn8UAAIIAAgJrhN5QgAFAgAIAAgJrhN5QgAFAgAAAA==.',
Bo='Boozerbear:BAAALgAECgkJAwAAAA==.Bornite:BAAALgADCgkJFQAAAA==.Bosstradamus:BAAALgAECgkJEAAAAA==.Bottombenoit:BAAALgADCgYJCgAAAA==.',
Br='Brewmanfu:BAABLgAECn8lAAMSAAkJrRVPGAD9AQASAAkJrRVPGAD9AQATAAQJIwkJXQCcAAAAAA==.Brewmaster:BAAALgADCgkJCQAAAA==.Brickaton:BAAALgAECgYJDgAAAA==.Brickdrag:BAAALgADCgYJBgABLgAECgYJDgAGAAAAAA==.Brionaimina:BAAALgADCgQJBAAAAA==.Brocknor:BAAALgAECgYJEwAAAA==.Brook:BAAALgADCgcJBwAAAA==.Brucebanners:BAAALgADCgIJAgABLgAECggJFwALAN8hAA==.Bruiseli:BAAALgAECgYJEAAAAA==.Brèdren:BAABLgAECn8wAAISAAgJhxoHBQDaAQASAAgJhxoHBQDaAQAAAA==.Brüh:BAAALgAECgcJCgAAAA==.',
Bu='Bucklebury:BAAALgADCgEJAQAAAA==.Bullogna:BAAALgAECgIJAgAAAA==.Burbon:BAAALgADCgMJAwABLgAECgYJFAATAIggAA==.Burstinatrix:BAAALgADCgEJAQAAAA==.Butterdtoast:BAEALgAECgYJDQAAAA==.',
['Bë']='Bëâst:BAAALgAECgIJAgAAAA==.',
Ca='Caboose:BAABLgAECn8aAAQUAAgJHx6ZAgBqAgAUAAcJHx6ZAgBqAgAVAAMJaApRGgHKAAAWAAMJgBFSCQC+AAAAAA==.Cadius:BAAALgADCgMJAwAAAA==.Caimera:BAAALgADCgkJFwAAAA==.Caledor:BAAALgAECgMJBAAAAA==.Calindrel:BAAALgAECgYJCAAAAA==.Caraway:BAAALgAECgUJBQAAAA==.Carcus:BAAALgADCggJCAAAAA==.Carysa:BAAALgADCgcJDgAAAA==.',
Ce='Celebrindal:BAAALgADCgkJHQAAAA==.Celticlore:BAAALgADCgkJIAAAAA==.Cerrvantes:BAAALgADCgMJAwAAAA==.Cesarius:BAAALgAECgQJDQAAAA==.',
Ch='Chappellroan:BAAALgAECgQJBAAAAA==.Charlemange:BAAALgADCgMJAwAAAA==.Charvein:BAAALgAECgQJBAAAAA==.Chernaboz:BAAALgAECgYJCgAAAA==.Chevelot:BAAALgADCgYJDAAAAA==.Chibbo:BAABLgAECn8WAAIXAAgJqAbyBABCAQAXAAgJqAbyBABCAQAAAA==.Chiblet:BAAALgAECgIJAgAAAA==.Chillblain:BAAALgADCgEJAQAAAA==.Chippendale:BAAALgADCgkJGwAAAA==.Chondre:BAAALgAECggJEgAAAA==.Chrigs:BAAALgAECgYJBwAAAA==.Chrispbacon:BAAALgADCgYJBgAAAA==.',
Co='Combustdeez:BAAALgADCgUJBQABLgAECggJIAAIAK0mAA==.Conrad:BAAALgADCgUJBQAAAA==.Copperknight:BAAALgAECgcJDgAAAA==.Corenthos:BAABLgAECn8aAAMYAAYJQx20GABOAQAYAAYJQx20GABOAQAZAAEJkRLfRgAsAAAAAA==.Cornelia:BAAALgAECgQJBAABLgAECgkJGQAKAJsGAA==.Cortanna:BAAALgADCgYJDgAAAA==.',
Cr='Cranker:BAAALgAECgMJBQAAAA==.Crashedot:BAAALgAECgQJBwAAAA==.Crazymoron:BAAALgADCggJCAAAAA==.Creselia:BAAALgAECgYJDgAAAA==.Cropduzzter:BAAALgADCgQJBAAAAA==.Crum:BAAALgAECgYJEAAAAA==.Cryptnotic:BAAALgADCgIJAgAAAA==.',
Cu='Cutthrøat:BAAALgAECgEJAQAAAA==.',
Cy='Cypherrellik:BAAALgAECgYJBgABLgAECgcJEwAGAAAAAA==.',
['Câ']='Câp:BAAALgAECgcJCAAAAA==.',
Da='Dablackmasta:BAABLgAECn8XAAIFAAgJbQ52DABZAQAFAAgJbQ52DABZAQAAAA==.Daftfunk:BAAALgADCggJCAAAAA==.Dagthunderer:BAAALgAECgUJBQAAAA==.Daidonks:BAAALgAECgMJBAAAAA==.Dakkenrahl:BAAALgAECgQJCAAAAA==.Dalistra:BAAALgAECgIJBQAAAA==.Dalweaver:BAAALgADCgMJAwABLgAECgIJBQAGAAAAAA==.Dalzz:BAAALgADCgYJBgABLgAECgIJBQAGAAAAAA==.Dantes:BAAALgADCgkJFAAAAA==.Dar:BAAALgAECgMJAwAAAA==.Darkaires:BAAALgAECgkJBgAAAA==.Darkflame:BAAALgAECgUJCQAAAA==.Darksidedbro:BAAALgADCgkJEQAAAA==.Darthvaeder:BAAALgAECgUJCgAAAA==.Davee:BAAALgADCgcJBwAAAA==.',
Dc='Dcpt:BAAALgADCgcJDwAAAA==.',
De='Deadgeinside:BAAALgAECgEJAQAAAA==.Deadgnome:BAAALgAECgEJAQABLgAECgYJEQAGAAAAAA==.Deathrose:BAAALgADCgkJCgAAAA==.Deathstomper:BAAALgAECgQJBgAAAA==.Delnarian:BAABLgAECn8UAAIMAAcJAh2DNwBFAgAMAAcJAh2DNwBFAgAAAA==.Demondono:BAAALgAECgYJEgAAAA==.Desmorphia:BAAALgADCgcJCQAAAA==.Destruir:BAAALgADCgkJCgAAAA==.Desy:BAAALgADCgQJBAABLgAECgcJFAAIAKIlAA==.Dethomonic:BAAALgADCgkJCQAAAA==.Devomo:BAABLgAECn8cAAILAAYJjSARQAD0AQALAAYJjSARQAD0AQAAAA==.Devoutsquirl:BAAALgADCgYJBgABLgAECgYJEgAGAAAAAA==.Deyedora:BAAALgAECgUJCQAAAA==.Deyjavaknadi:BAAALgADCgMJAwAAAA==.',
Di='Diegodruida:BAAALgADCgUJBQAAAA==.Dilligafnope:BAAALgADCgkJEgAAAA==.Dinkster:BAAALgAECgYJDQAAAA==.Dinohunter:BAAALgAECgcJDwAAAA==.Dinokat:BAAALgADCgIJAgABLgAECggJIgAIALkWAA==.Dirtslinger:BAAALgAECgMJAwAAAA==.Disabler:BAABLgAECn8gAAMIAAgJrSZvAAAeAwAIAAgJrSZvAAAeAwAJAAEJ7yHKWQBhAAAAAA==.Discotits:BAAALgAECgEJAQAAAA==.',
Do='Dokesa:BAABLgAECn8VAAMYAAcJ0R3fQwAqAgAYAAYJQyHfQwAqAgAZAAEJlwzlRwApAAAAAA==.Dolfratt:BAAALgAECgQJBAABLgAECgkJJQASAK0VAA==.Dooknukem:BAAALgADCgYJBgAAAA==.Doomguard:BAAALgADCgkJDwAAAA==.Dorimane:BAAALgAECgYJEgAAAQ==.Dorlock:BAAALgAECgYJEQAAAA==.Dortivi:BAAALgADCgYJBwAAAA==.Dotdôtdot:BAAALgADCgIJAgAAAA==.Dotrastraez:BAAALgADCgIJAgAAAA==.Dotvader:BAAALgAECgcJDAAAAA==.',
Dr='Draklee:BAAALgAECgEJAgAAAA==.Draxestraza:BAAALgADCgcJFwAAAA==.Draykey:BAAALgAECgEJAQABLgAECgcJGAAEADAdAA==.Draykeyy:BAABLgAECn8YAAIEAAcJMB0jIgA1AgAEAAcJMB0jIgA1AgAAAA==.Dred:BAAALgADCgYJDwAAAA==.Dredwarrior:BAABLgAECn8UAAMFAAgJwQ/5XQA3AQAFAAYJSBD5XQA3AQAaAAUJUQuIJwCyAAAAAA==.Drenlei:BAAALgAECgcJBwAAAA==.Drood:BAAALgAECgEJAQAAAA==.Drotara:BAAALgAECgYJDQAAAA==.Drprodigy:BAABLgAECn8cAAILAAgJVxVbPAADAgALAAgJVxVbPAADAgAAAA==.Drunkbaby:BAAALgAECggJEQAAAA==.',
Dy='Dynasty:BAAALgADCgkJFQAAAA==.Dyrcyn:BAAALgAECgEJAQAAAA==.',
['Dà']='Dàddy:BAAALgAECgEJAQAAAA==.Dànger:BAAALgAECgkJBgAAAA==.',
Ed='Edrius:BAAALgAECgMJAwAAAA==.Edroh:BAAALgAECgYJEgAAAA==.',
Eh='Ehsera:BAAALgADCgUJBgAAAA==.',
Ei='Eidur:BAABLgAECn8UAAMbAAcJdxdcCQCrAQAbAAYJFhtcCQCrAQAcAAUJ7BZePAA4AQAAAA==.',
El='Elando:BAAALgADCgMJAwAAAA==.Elegies:BAABLgAECn8lAAILAAgJ/h00CADvAQALAAgJ/h00CADvAQAAAA==.Elfater:BAAALgADCgQJBAAAAA==.Eliarace:BAAALgADCgMJAwAAAA==.Eljeffesan:BAAALgADCgcJFwAAAA==.Elspeth:BAAALgADCgYJBgABLgAECgYJDQAGAAAAAA==.Elythria:BAAALgAECgQJBwAAAA==.',
Em='Emagonadye:BAACLgAFFH8HAAIdAAMJ1SH6BAArAQAdAAMJ1SH6BAArAQAuAAQKfxQAAh0ACAmjJFIEAEcDAB0ACAmjJFIEAEcDAAAA.Emlee:BAAALgADCgIJAgAAAA==.Emporersmaug:BAAALgADCgEJAQAAAA==.',
En='Endugu:BAAALgAECgYJBwAAAA==.Enflamee:BAAALgAECgcJDQABLgAECgcJGwAPAOAgAA==.Enforcer:BAABLgAECn8UAAMIAAgJiBmGKgDiAAAIAAYJQhmGKgDiAAAJAAMJ+xTYOgDJAAAAAA==.Engath:BAAALgAECgYJDAABLgAECgcJGwAPAOAgAA==.',
Er='Erikprince:BAAALgADCgEJAgAAAA==.Erosonia:BAAALgAECgQJBQAAAA==.Erso:BAAALgADCgYJCAAAAA==.',
Es='Espresso:BAAALgAECgcJDwAAAA==.',
Et='Eternalpaín:BAABLgAECn8eAAIMAAgJlBnhPQAtAgAMAAgJlBnhPQAtAgAAAA==.',
Ev='Evanee:BAAALgAECgYJDAAAAA==.',
Ez='Ezykeul:BAAALgAECgQJCAAAAA==.',
Fa='Fal:BAAALgAECggJEQAAAA==.Falcyon:BAAALgADCgMJAwAAAA==.Fallenson:BAAALgAECgEJAQAAAA==.',
Fe='Felbrooks:BAAALgADCgkJFQAAAA==.Felmommy:BAAALgADCgcJAQAAAA==.Felsông:BAAALgADCgcJBwAAAA==.Fendretta:BAABLgAECn8YAAINAAYJTBNBFQBRAQANAAYJTBNBFQBRAQAAAA==.',
Fi='Firefawkes:BAAALgAECgQJBAAAAA==.Fistbump:BAAALgADCgYJDAAAAA==.Fivepiece:BAAALgADCgcJBwAAAA==.Fixzie:BAAALgAECgcJDgAAAA==.',
Fl='Flah:BAAALgAECggJCgAAAA==.Flip:BAAALgAECgcJBwAAAA==.Flizrak:BAAALgAECgYJCwABLgAFFAYJEwAVAK8fAA==.',
Fo='Forestflex:BAAALgAECgYJBgAAAA==.Foxstrazagos:BAAALgADCgkJCwAAAA==.',
Fr='Friggnar:BAAALgADCgYJBwAAAA==.Frostsalad:BAAALgADCgQJBAAAAA==.Frostynugz:BAAALgADCgYJCQAAAA==.',
Fu='Fulta:BAABLgAECn8VAAICAAYJKhusMACuAQACAAYJKhusMACuAQAAAA==.',
Fy='Fyra:BAAALgADCggJCAABLgAECggJFQAMAAQWAA==.',
['Fí']='Fírnen:BAAALgAECgQJBwAAAA==.',
Ga='Gailz:BAAALgADCgQJBAAAAA==.Gammb:BAAALgAECgEJAQAAAA==.Garadin:BAAALgAECgYJEwAAAA==.Garcona:BAAALgAECgMJBQAAAA==.Garqman:BAAALgADCgUJBQAAAA==.Garwa:BAAALgAECgMJCAAAAA==.',
Ge='Geniver:BAAALgAECgMJBgAAAA==.Gerken:BAAALgAECgIJAgAAAA==.Gerkenator:BAAALgAECgMJAwAAAA==.Gerla:BAAALgAECgYJCwAAAA==.',
Gh='Ghettoshout:BAAALgAECgMJBAAAAA==.',
Gi='Gialania:BAAALgAECgYJEgAAAA==.Gilgameshh:BAAALgADCgkJEAAAAA==.Girthbrook:BAAALgADCgcJCAAAAA==.Girthbrooks:BAAALgADCgQJBAAAAA==.Girthtrude:BAABLgAECn8ZAAILAAgJHAYvHAAhAQALAAgJHAYvHAAhAQAAAA==.',
Gl='Glaivertoss:BAAALgAECgYJCAAAAA==.Glorythighs:BAAALgADCgEJAQAAAA==.Glycerol:BAAALgADCgUJBQAAAA==.',
Go='Goblincox:BAAALgAECgUJBwAAAA==.Gomory:BAAALgAECgMJBgAAAA==.Gondark:BAAALgAECgQJBAAAAA==.Goobly:BAABLgAECn8cAAIcAAYJsReULACaAQAcAAYJsReULACaAQAAAA==.Gooseblade:BAAALgADCgUJBQAAAA==.Goregrimm:BAAALgAECgEJAQAAAA==.Gorgoz:BAAALgADCgEJAQAAAA==.Gorgrim:BAAALgADCgMJAwAAAA==.',
Gr='Gregòr:BAAALgAECgkJBQAAAA==.Gretchen:BAABLgAECn8mAAMYAAgJlRWbCQDlAQAYAAgJlRWbCQDlAQAZAAQJbAivNgCMAAAAAA==.Greywolf:BAABLgAECn8cAAIRAAgJtxouBgD2AQARAAgJtxouBgD2AQAAAA==.Grezin:BAAALgADCgEJAQAAAA==.Grimlight:BAABLgAFFH8GAAIMAAMJ2hzIEQAXAQAMAAMJ2hzIEQAXAQABLgAFFAYJEQAYAC0bAA==.Grimtorr:BAAALgADCgMJAwAAAA==.Ground:BAAALgAECgQJBQAAAA==.Grymlee:BAAALgAECgQJBgAAAA==.Grëgor:BAAALgAECgMJAwAAAA==.',
Gu='Guinènvere:BAAALgAECgYJEAAAAA==.',
['Gä']='Gärry:BAAALgAECgEJAQAAAA==.',
['Gö']='Gökù:BAAALgADCgQJBAAAAA==.',
Ha='Haedes:BAAALgAECgMJAwABLgAECgYJCgAGAAAAAA==.Haktori:BAAALgAECgYJBwAAAA==.Hammerknee:BAAALgAECgcJDgAAAA==.Hariku:BAAALgAECgQJBgAAAA==.Harleii:BAAALgAECgcJDgAAAA==.Harlequins:BAAALgADCggJDgAAAA==.Harmonix:BAAALgAECgkJBAAAAA==.Harrow:BAAALgAECgQJBwAAAA==.Hastler:BAAALgADCgkJCQAAAA==.Hawt:BAAALgAECgEJBAAAAA==.',
He='Hearge:BAABLgAECn8dAAMeAAkJzBtbDQCuAgAeAAkJzBtbDQCuAgAMAAYJVQgBuwAQAQAAAA==.Heckatae:BAAALgAECgQJCAAAAA==.Hellborne:BAAALgADCgIJAgAAAA==.Hellhawk:BAAALgAECgYJDQAAAA==.Helwe:BAAALgAECgEJAgAAAA==.Heptandew:BAAALgAECgQJBAAAAA==.',
Hi='Hikkio:BAAALgADCgMJAwAAAA==.',
Ho='Holycheeks:BAAALgADCgYJBgAAAA==.Holychib:BAAALgAECgYJCAAAAA==.Holypho:BAAALgADCgYJDAAAAA==.Holysheet:BAAALgAECgYJCAAAAA==.Holystan:BAAALgAECgUJDgAAAA==.Hondoe:BAAALgAECgQJBQAAAA==.Honorable:BAAALgADCgEJAQABLgAECgkJJQASAK0VAA==.Hoshino:BAAALgADCgYJBwABLgADCgYJDAAGAAAAAA==.Hoshiyoru:BAAALgADCggJFAAAAA==.Houki:BAAALgAECgYJDwAAAA==.',
Hp='Hpylorii:BAAALgAECgYJEgAAAA==.',
Ht='Htownhunter:BAAALgAECgIJAgAAAA==.Htownprot:BAAALgAFFAIJAgAAAA==.',
Hu='Hungovertank:BAACLgAFFH8PAAIdAAUJ2h+6BQB4AQAdAAUJ2h+6BQB4AQAuAAQKfy0AAh0ACAmIJQ4EAEwDAB0ACAmIJQ4EAEwDAAAA.Hungzilla:BAABLgAECn8TAAMfAAcJ9xW3HgDOAQAfAAcJBxS3HgDOAQAgAAMJvw+0LgCiAAAAAA==.Huntfromhell:BAAALgAECgYJDQAAAA==.Hurkano:BAAALgADCgUJCQAAAA==.',
Ig='Ignisfatuus:BAAALgAECgYJCgAAAA==.',
Il='Ilarion:BAAALgADCggJEgAAAA==.Illio:BAAALgAECgMJAwAAAA==.Illyasviel:BAAALgADCgcJBwAAAA==.',
Im='Imarea:BAAALgAECgYJEgAAAA==.Impirious:BAAALgAECgYJDgAAAA==.Imppimp:BAAALgAECgEJAQAAAA==.Imtryntotank:BAABLgAECn8UAAIeAAYJYgzfUAA1AQAeAAYJYgzfUAA1AQAAAA==.Imyx:BAAALgAECgYJEAAAAA==.',
In='Infamuspikel:BAAALgAECggJEAAAAA==.Infel:BAAALgAECgkJDQAAAA==.Inkkish:BAAALgAECgMJAwAAAA==.Innovates:BAAALgAECgQJDAAAAA==.Innowar:BAAALgADCgYJBgAAAA==.Intervene:BAAALgADCgMJAwABLgAECggJHgAMAJQZAA==.Invictus:BAAALgAECgYJDQAAAA==.',
Io='Iota:BAAALgAECgYJEwAAAA==.',
Ir='Irminarae:BAAALgAECgYJEwAAAA==.',
Is='Isa:BAAALgADCgEJAQAAAA==.Isaßeau:BAAALgADCgcJCwAAAA==.',
Ja='Jandoar:BAAALgAECgYJEAAAAA==.Jarlen:BAAALgADCgcJCgAAAA==.Jasmil:BAAALgADCgUJCAAAAA==.Jaylah:BAAALgADCgUJBgAAAA==.',
Je='Jezala:BAAALgADCgkJGQAAAQ==.',
Ji='Jiq:BAAALgADCgUJBwAAAA==.',
Jo='Johli:BAAALgADCgkJCQAAAA==.',
['Jö']='Jördyn:BAAALgADCgMJAwAAAA==.',
Ka='Kabilos:BAAALgAECgMJAwAAAA==.Kaboòm:BAABLgAECn8hAAIVAAgJcRC2fQDWAQAVAAgJcRC2fQDWAQAAAA==.Kaedian:BAAALgADCgQJBAABLgAECgYJFAATAIggAA==.Kaelthazad:BAAALgADCgEJAQAAAA==.Kagamai:BAAALgADCgUJBQAAAA==.Kagaramar:BAAALgAECgEJAQAAAA==.Kalesmora:BAAALgAECgYJEAAAAA==.Kaluu:BAAALgAECgEJAQABLgAECgEJAQAGAAAAAA==.Kamikaze:BAAALgAECgcJEQAAAA==.Kaorî:BAAALgADCgEJAQAAAA==.Karlov:BAAALgAECgcJEgAAAA==.Katebush:BAAALgAECgIJAgAAAA==.Kaydahlia:BAAALgAECgEJAQAAAA==.',
Ke='Keheo:BAAALgAECgEJAQAAAA==.Kelithiena:BAAALgADCgMJBQAAAA==.',
Kh='Khaziel:BAAALgAECgUJBQAAAA==.Kheims:BAAALgAECgQJBAAAAA==.Khri:BAAALgADCgYJBgAAAA==.Khuzdul:BAAALgADCgQJBAAAAA==.',
Ki='Kidcat:BAAALgAECgMJBQAAAA==.Kiddemon:BAAALgADCgcJCAAAAA==.Killduran:BAAALgAECggJDwAAAA==.Kimiyo:BAAALgADCgcJCAAAAA==.Kimpossumble:BAAALgAECgMJAwAAAA==.Kinetic:BAAALgADCgkJEAAAAA==.Kirasha:BAAALgADCgIJAgAAAA==.',
Kl='Kleopatra:BAABLgAECn8YAAMTAAYJtwXxRwD1AAATAAYJtwXxRwD1AAAdAAIJ8gIWhAA/AAAAAA==.Klunt:BAAALgADCgcJCAABLgAECgYJEQAGAAAAAA==.',
Kn='Knitehunt:BAAALgAECgMJAwAAAA==.Knives:BAAALgAECgQJBwAAAA==.',
Ko='Kochiyo:BAAALgADCgcJDQAAAA==.Korgal:BAAALgADCgYJDAAAAA==.Kortar:BAAALgADCgUJCgAAAA==.Kotros:BAAALgAECgEJAQAAAA==.',
Kr='Kracked:BAAALgAECgIJAgABLgAECgQJDQAGAAAAAA==.Kreigan:BAAALgADCgkJCQAAAA==.Krelid:BAAALgADCgkJEAABLgAECgYJEgAGAAAAAA==.Krellyroll:BAAALgAECgYJEgAAAA==.Krelthyr:BAAALgADCgkJCQABLgAECgYJEgAGAAAAAA==.Krumm:BAABLgAECn8ZAAIhAAYJ6QPiDACrAAAhAAYJ6QPiDACrAAAAAA==.Krumpas:BAAALgADCgcJDgAAAA==.Kryvea:BAAALgADCggJCAAAAA==.',
Ku='Kuhne:BAAALgADCgkJDwAAAA==.Kurno:BAAALgADCgcJEwAAAA==.Kuromie:BAAALgADCgIJAgABLgAECggJCgAGAAAAAA==.',
Ky='Kyboom:BAAALgADCgYJBgAAAA==.',
['Kà']='Kàlluu:BAAALgAECgEJAQAAAA==.',
['Kñ']='Kñightboat:BAAALgAECgYJEAAAAA==.',
La='Ladeiene:BAAALgAECgIJAgAAAA==.Laelwyn:BAAALgAECgMJBQAAAA==.Laelynd:BAAALgADCgYJBgAAAA==.Lardna:BAAALgAECgEJAQAAAA==.',
Le='Leathermommy:BAAALgAECgUJCwAAAA==.Leges:BAABLgAECn8UAAIIAAYJkCNmBwD7AQAIAAYJkCNmBwD7AQAAAA==.Lehong:BAABLgAECn8XAAMdAAgJChUMBQDFAQAdAAgJChUMBQDFAQATAAEJWgfNgwAsAAAAAA==.Lejion:BAAALgAECgYJEAAAAA==.Lethariel:BAAALgAECgIJAgAAAA==.Lethas:BAAALgAECggJDAAAAA==.',
Li='Liandrys:BAAALgADCgUJCwAAAA==.Lightrising:BAAALgAECgIJBAAAAA==.Lilfreya:BAAALgADCgQJBAAAAA==.Lilmonstrman:BAABLgAECn8ZAAMVAAgJZBL8EQCyAQAVAAgJ8BD8EQCyAQAUAAYJzhHPCABjAQAAAA==.Limbbiscuit:BAAALgADCgYJBgAAAA==.Linger:BAAALgAECgcJEQAAAA==.Linnet:BAAALgAECgEJAQAAAA==.Litany:BAABLgAECn8YAAIeAAYJyxIdDQBtAQAeAAYJyxIdDQBtAQAAAA==.Liya:BAAALgAECgYJDQAAAA==.',
Lo='Lokith:BAAALgAECgEJAQAAAA==.Lorilai:BAAALgAECgEJAQAAAA==.Loroke:BAAALgADCgkJCwAAAA==.Lots:BAAALgAECgEJAQAAAA==.',
Lu='Lucinâ:BAAALgADCgcJAgAAAA==.Lucith:BAAALgADCgUJBwAAAA==.Lul:BAACLgAFFH8KAAIFAAMJ8h76BAASAQAFAAMJ8h76BAASAQAuAAQKfyIAAwUABwmhI3IQAM4CAAUABwmZI3IQAM4CABoABgltHb0KAPgBAAAA.Lumpthumb:BAAALgADCgMJAwAAAA==.Lunaaru:BAAALgAECgMJAwABLgAECggJGwAEAN0fAA==.Lunamay:BAABLgAECn8bAAIEAAgJ3R95DwC9AgAEAAgJ3R95DwC9AgAAAA==.',
['Lð']='Lðvergirl:BAAALgAECgEJAQAAAA==.',
['Lò']='Lòck:BAAALgAECgEJAQAAAA==.',
['Ló']='Lóki:BAAALgADCgEJAQAAAA==.',
Ma='Machotaco:BAAALgADCgMJAwAAAA==.Maddieketh:BAAALgADCgMJAwAAAA==.Maeghor:BAABLgAECn8bAAIVAAcJWReXhQDGAQAVAAcJWReXhQDGAQAAAA==.Maelleam:BAAALgAECgQJBAAAAA==.Magicash:BAAALgAECgQJCQAAAA==.Magistella:BAAALgAECgYJBgAAAA==.Magmadh:BAAALgAECgEJAgAAAA==.Malignantt:BAAALgAECgYJEgAAAA==.Manastress:BAAALgAECgQJBQAAAA==.Mapletoast:BAAALgADCgQJBAAAAA==.Maskerade:BAAALgADCgUJBQAAAA==.Maurphious:BAAALgADCgkJHQAAAA==.Mavraela:BAAALgADCgUJDQAAAA==.',
Me='Meenhoe:BAAALgADCgUJBQAAAA==.Melee:BAAALgADCgcJBwAAAA==.Meleena:BAAALgADCgEJAQAAAA==.Mellecarde:BAAALgADCgQJBAAAAA==.Melodrama:BAAALgAECgIJAgAAAA==.Messadin:BAAALgAECgYJEgAAAA==.Metalguard:BAAALgADCgUJBQAAAA==.Metri:BAAALgAECgUJDgAAAA==.',
Mi='Michelleyeoh:BAAALgADCgUJBQABLgAECgYJDAAGAAAAAA==.Mikearoni:BAABLgAECn8XAAMfAAcJgBJCJACbAQAfAAYJpBRCJACbAQAiAAEJeAHpTQAkAAAAAA==.Mirgaree:BAAALgAECgYJDgAAAA==.Mistweaving:BAACLgAFFH8MAAISAAQJCyWlAQCsAQASAAQJCyWlAQCsAQAuAAQKfyMAAxIACAlMI0kGAPsCABIACAlMI0kGAPsCABMABAnNFRFMAOIAAAAA.',
Mo='Moistweaver:BAABLgAECn8bAAISAAcJoxtdFgARAgASAAcJoxtdFgARAgAAAA==.Mommystrasza:BAAALgAECgMJAwAAAA==.Monkfall:BAAALgADCgMJAwABLgAECggJFAAZAOgcAA==.Monkoreo:BAAALgADCgQJBAAAAA==.Monkwrld:BAABLgAECn8dAAITAAgJZB0hBADEAQATAAgJZB0hBADEAQAAAA==.Monty:BAAALgAECgYJBgAAAA==.Moosemode:BAAALgADCgcJBwAAAA==.Mordet:BAAALgADCgUJBQABLgAECgYJEgAGAAAAAQ==.Moridane:BAAALgAECgEJAQABLgAECgYJEgAGAAAAAQ==.',
Mu='Muffinz:BAAALgAECgYJEQAAAA==.',
My='Myau:BAAALgAECgYJEAAAAA==.Myera:BAAALgADCgUJBQAAAA==.Mynia:BAABLgAECn8YAAIBAAYJ9wxjCAApAQABAAYJ9wxjCAApAQAAAA==.Mythrius:BAAALgAECgUJCwAAAA==.',
['Mø']='Mørdu:BAAALgADCgcJBwAAAA==.',
Na='Nada:BAAALgAECgQJBAAAAA==.Nano:BAAALgAECgYJEgAAAA==.Nardor:BAAALgAECgYJDgAAAA==.Naturelle:BAAALgAECgYJEAAAAA==.Nautilius:BAAALgADCggJDwAAAA==.Navaani:BAABLgAECn8YAAIjAAcJXx7mAQD2AQAjAAcJXx7mAQD2AQAAAA==.Nazdreg:BAACLgAFFH8FAAIIAAMJMAr2OQCfAAAIAAMJMAr2OQCfAAAuAAQKfxoAAwgABwm7HJEzAD4CAAgABwm7HJEzAD4CAAkAAQkAAHGBAAYAAAAA.Nazgull:BAAALgAECgIJAgAAAA==.',
Ne='Neisa:BAAALgADCgMJAwAAAA==.Nemesicc:BAAALgAECgUJDAAAAA==.Neotoldir:BAABLgAECn8XAAIkAAYJwhXcAgA0AQAkAAYJwhXcAgA0AQAAAA==.Nerfdisc:BAAALgAECgQJBwAAAA==.Nerfdruids:BAAALgADCgUJBQAAAA==.Nerozond:BAAALgAECgEJAgAAAA==.Netalli:BAABLgAECn8UAAIVAAgJmyB2JwDUAgAVAAgJmyB2JwDUAgABLgABCgQJBAAGAAAAAA==.Nevershocked:BAAALgAECgcJDgAAAA==.Nezziee:BAAALgAECgYJCAAAAA==.',
Ni='Nibroc:BAAALgAECgUJBQAAAA==.Nidhoggy:BAAALgAECgYJEAAAAA==.Nife:BAAALgAECgEJAQAAAA==.',
No='Nordie:BAAALgAECgcJEgAAAA==.Northik:BAABLgAECn8cAAMYAAgJXiBUHwDFAgAYAAgJXiBUHwDFAgAZAAYJ4Q0nCQD1AAAAAA==.Notintheface:BAAALgAECgYJEAAAAA==.',
Nu='Numlock:BAAALgAECgMJAwAAAA==.',
Ny='Nydav:BAABLgAECn8UAAITAAYJiCCGFQA+AgATAAYJiCCGFQA+AgAAAA==.Nystallina:BAAALgADCgMJAwAAAA==.',
['Ní']='Níítefall:BAABLgAECn8bAAIPAAcJ4CB3AwCbAgAPAAcJ4CB3AwCbAgAAAA==.',
Oa='Oakbreaker:BAAALgAECgEJAQABLgAECgcJGQAcAOYgAA==.',
Ob='Obalma:BAAALgAECgQJBAAAAA==.',
Od='Odrade:BAAALgADCgIJAgAAAA==.Odwalla:BAACLgAFFH8LAAINAAQJTh+AAACaAQANAAQJTh+AAACaAQAuAAQKfyMABA0ACAlQIw4KAPgCAA0ACAlQIw4KAPgCAAEABgmtHykVAHUBAAIAAwkMFD5kAK8AAAAA.',
Oh='Ohgodno:BAAALgAECgcJDQAAAA==.',
Ok='Oktal:BAAALgAECgYJBgAAAA==.',
Ol='Olmec:BAABLgAECn8aAAIlAAgJ8hECBwCYAQAlAAgJ8hECBwCYAQAAAA==.',
On='Onlydesert:BAAALgAECgIJAgAAAA==.',
Oo='Oorudun:BAAALgADCgYJBgAAAA==.',
Op='Ophiel:BAAALgADCgYJDwAAAA==.Optiks:BAAALgAECgYJDQAAAA==.',
Or='Orblio:BAAALgADCgQJBAAAAA==.Orcofhell:BAAALgADCggJCQAAAA==.Orcthas:BAAALgAECgMJBQAAAA==.Orksauce:BAABLgAECn8ZAAMcAAcJ5iAZAgAlAgAcAAcJ5iAZAgAlAgAbAAEJ2RYGHABIAAAAAA==.Orleron:BAAALgADCgkJDAAAAA==.Oroth:BAAALgAECgMJCQAAAA==.',
Os='Osares:BAAALgAECgUJCAAAAA==.Oshizitskoro:BAAALgAECgEJAQAAAA==.',
Ot='Otsu:BAAALgADCgMJAwABLgAECgUJDQAGAAAAAA==.',
Ou='Outofwater:BAAALgADCgYJBgAAAA==.Outtyfox:BAAALgADCgIJAgAAAA==.',
['Oß']='Oß:BAAALgAECgEJAQABLgAECggJJgATALkQAA==.',
Pa='Pagophobia:BAAALgADCgEJAQAAAA==.Pakku:BAAALgAECgUJCwAAAA==.Pallytree:BAAALgAECgQJBQAAAA==.Pantheeon:BAAALgADCgIJAgAAAA==.Parzival:BAAALgAECgcJEQAAAA==.Patchface:BAAALgADCgcJBwAAAA==.',
Pd='Pdp:BAABLgAECn8VAAIDAAcJiCO2FgBXAgADAAcJiCO2FgBXAgAAAA==.',
Pe='Perkbane:BAAALgAECgcJEgAAAA==.Perkdragon:BAAALgAECgYJBQABLgAECgcJEgAGAAAAAA==.Perkyl:BAAALgAECgQJBgAAAA==.Petrol:BAAALgAECgYJBwAAAA==.',
Ph='Phage:BAAALgAECgEJAQABLgAECgYJEQAGAAAAAA==.Pheel:BAAALgAECgUJBQAAAA==.Phillactery:BAAALgAECgEJAQAAAA==.Phlykz:BAAALgADCgEJAQAAAA==.Phosho:BAAALgADCgYJBgAAAA==.',
Pi='Pig:BAAALgAECgQJBAAAAA==.Pikevarr:BAAALgAECgMJAwAAAA==.',
Pk='Pkrage:BAABLgAECn8gAAMhAAgJRhrpCwBOAgAhAAgJRhrpCwBOAgAFAAEJTAAjtwAIAAAAAA==.',
Pl='Plagueborne:BAAALgAECgYJBgAAAA==.Plazzy:BAABLgAECn8dAAIcAAgJ/hqPDwCsAgAcAAgJ/hqPDwCsAgAAAA==.Plopp:BAEALgAECgUJCwAAAA==.',
Po='Polyethylene:BAAALgAECgYJEAAAAA==.',
Pr='Pretzel:BAAALgAECgEJAgABLgAECgYJEgAGAAAAAQ==.Proxymate:BAAALgADCgMJAwAAAA==.',
Pu='Puhtty:BAAALgADCgQJBAAAAA==.Punkfangs:BAAALgADCgcJDwAAAA==.',
['Pë']='Pëaches:BAAALgADCgcJBwABLgAFFAUJDQALABELAA==.',
['Pï']='Pï:BAAALgAECgQJBgAAAA==.',
Qk='Qkoira:BAAALgADCgYJBgABLgADCgcJCgAGAAAAAA==.',
Qu='Quanlain:BAAALgAECgcJEAAAAA==.Quasár:BAAALgAECgYJCgAAAA==.Quilara:BAAALgADCgkJHQAAAA==.Quillathe:BAABLgAECn8aAAMKAAYJuhVKBQC5AQAKAAYJuhVKBQC5AQAmAAEJbQYeZQAuAAAAAA==.',
Ra='Radíant:BAAALgADCgUJBQABLgABCgYJBgAGAAAAAA==.Ragemaster:BAAALgAECgQJCQAAAA==.Ramiusraven:BAAALgADCgIJAgAAAA==.Rancore:BAAALgAECggJEgAAAA==.Rashdar:BAABLgAECn8VAAIMAAgJBBaPQwAaAgAMAAgJBBaPQwAaAgAAAA==.Rattpack:BAAALgAECgYJDwAAAA==.Raves:BAABLgAECn8UAAIVAAYJUiDwVwAxAgAVAAYJUiDwVwAxAgAAAA==.',
Re='Regilz:BAAALgAECgIJAgAAAA==.Reselience:BAAALgAECgQJBAABLgAECggJGgAIAAggAA==.',
Rh='Rhadamenth:BAAALgADCgMJAwAAAA==.Rhinity:BAAALgADCgQJBAABLgAECgYJEwAGAAAAAA==.Rhyolite:BAAALgADCgkJDwAAAA==.',
Ri='Riaeviana:BAAALgAECgYJDwAAAA==.Ribeyye:BAAALgAECgUJBgAAAA==.Rigormistis:BAAALgADCgEJAQAAAA==.Rilde:BAAALgADCgcJBwAAAA==.Rinjielune:BAAALgADCgYJDwAAAA==.Risch:BAAALgAECgMJAwAAAA==.Rius:BAAALgADCgIJAgAAAA==.',
Ro='Roberts:BAAALgADCgkJEAAAAA==.Robroÿ:BAAALgAECgYJCwAAAA==.Robrõy:BAAALgAECgkJBAABLgAECgkJBgAGAAAAAA==.Roku:BAAALgAECgYJCAABLgAFFAUJFAAIABkgAA==.Romex:BAAALgADCgEJAQAAAA==.Rondo:BAAALgADCgUJBQAAAA==.Roseclaw:BAEALgAECgYJBgAAAA==.Roseclawed:BAEALgAECgUJCQABLgAECgYJBgAGAAAAAA==.Roxso:BAACLgAFFH8TAAIVAAYJrx+hBwDnAQAVAAYJrx+hBwDnAQAuAAQKfx0AAhUACQl+JKACANUDABUACQl+JKACANUDAAAA.',
Ru='Runnigan:BAAALgADCgQJBAAAAA==.',
Rx='Rxse:BAAALgAECgYJBgAAAA==.',
Ry='Rylun:BAAALgADCgYJCQAAAA==.',
['Rà']='Rànik:BAAALgADCgIJAgAAAA==.',
['Rë']='Rëdmagma:BAAALgAECggJEQAAAA==.',
Sa='Saasaki:BAAALgAECgUJDQAAAA==.Sabrinacarp:BAABLgAECn8aAAIeAAcJxho8IQATAgAeAAcJxho8IQATAgAAAA==.Sabryelle:BAAALgADCgEJAgAAAA==.Sacrelicious:BAAALgAECgYJDgAAAA==.Sagewynn:BAAALgAECgUJBQAAAA==.Salfroc:BAABLgAECn8ZAAMHAAYJcxAeAgBWAQAHAAYJcxAeAgBWAQAJAAEJ9AHFfgAbAAAAAA==.Saltychief:BAAALgADCgUJBwAAAA==.Saplo:BAABLgAECn8WAAINAAgJxgiEFQBPAQANAAgJxgiEFQBPAQAAAA==.Sapphiraflux:BAAALgADCgIJAgAAAA==.Sarif:BAAALgADCgcJDAAAAA==.Sarvashi:BAAALgAECgMJBAAAAA==.Sasara:BAAALgAECgMJBgAAAA==.Saxel:BAAALgAECggJDQAAAA==.',
Sc='Scrabble:BAAALgADCgUJBQAAAA==.',
Se='Segio:BAAALgAECgcJDQAAAA==.Selcia:BAAALgAECgQJBwAAAA==.Serenati:BAAALgAECgcJEAAAAA==.Sermour:BAAALgAECgEJAQAAAA==.',
Sh='Shadephoenix:BAAALgAECgYJEQAAAA==.Shados:BAAALgAFFAEJAQAAAA==.Shadowen:BAAALgAECgQJBwAAAA==.Sharavia:BAAALgAECgYJEAAAAA==.Shari:BAAALgAECgYJEQAAAA==.Shatoo:BAAALgAECgYJDwAAAA==.Shaunchaos:BAAALgADCgMJAwAAAA==.Shaunrawr:BAABLgAECn8XAAMNAAcJPxZ7EgBoAQANAAcJPxZ7EgBoAQACAAIJ5wXmewBUAAAAAA==.Shield:BAAALgADCgMJAwAAAA==.Shiftedtea:BAAALgADCgcJCQAAAA==.Shizaxe:BAAALgADCgUJBQAAAA==.Shizish:BAAALgAECgYJEgAAAA==.Shocktuah:BAABLgAECn8aAAIlAAYJmiSUBADeAQAlAAYJmiSUBADeAQAAAA==.Shonúff:BAABLgAECn8aAAMTAAYJThzmBwBbAQATAAYJThzmBwBbAQASAAUJUgngRQDGAAAAAA==.Shotaro:BAAALgAECgUJDAAAAA==.',
Si='Sillybear:BAAALgAECgQJBQAAAA==.Sinful:BAABLgAECn8fAAMNAAgJUhKHLgD3AQANAAgJUhKHLgD3AQACAAMJ6AAofwBJAAAAAA==.Singarti:BAAALgAECggJDgAAAA==.Sizzlesnout:BAAALgAECgMJAwAAAA==.',
Sk='Skalagrim:BAAALgADCgMJAwAAAA==.Skedu:BAAALgADCgEJAQAAAA==.Skeptyk:BAAALgAECgYJEQAAAA==.Skolivia:BAEBLgAECn8VAAMmAAgJCBdfGQAWAgAmAAgJCBdfGQAWAgAKAAIJXxCbSQBxAAAAAA==.Skroggo:BAAALgAECgEJAgAAAA==.Skådoosh:BAABLgAECn8mAAMTAAgJuRDMBgBzAQATAAgJuRDMBgBzAQAdAAQJtAgxawCVAAAAAA==.',
Sl='Slightdawn:BAAALgADCgkJCQAAAA==.Sloppymop:BAAALgADCgUJCAAAAA==.Sloppysteaks:BAAALgADCgUJBQAAAA==.',
Sm='Smallben:BAAALgADCgIJAgAAAA==.Smiley:BAAALgAECgYJDgAAAA==.Smite:BAAALgADCgIJAgAAAA==.Smitti:BAAALgAECgMJAwAAAA==.Smug:BAABLgAECn8bAAILAAgJhCQTAgChAgALAAgJhCQTAgChAgAAAA==.',
Sn='Snapcrklepop:BAAALgADCgUJBQAAAA==.Sniffledoo:BAAALgAECgYJDQAAAA==.Snuwuf:BAAALgADCgEJAQAAAA==.Snóóf:BAAALgAECgQJCAAAAA==.',
So='Solomeani:BAAALgAECgMJBAAAAA==.Sonicnoah:BAAALgADCgYJDQAAAA==.Sourfangs:BAABLgAECn8WAAIFAAgJESWiBQBNAwAFAAgJESWiBQBNAwAAAA==.Soxx:BAAALgAECgEJAQAAAA==.',
Sp='Sparklymayhm:BAAALgADCgcJCwAAAA==.Spearz:BAAALgADCgQJBAAAAA==.Speedmonster:BAAALgADCggJCAAAAA==.Spicymilk:BAABLgAECn8fAAIUAAgJWyH1AQCTAgAUAAgJWyH1AQCTAgAAAA==.Spicypeño:BAABLgAECn8bAAMgAAcJaiE7DAAXAgAgAAYJPiE7DAAXAgAfAAUJFB3MIgCnAQABLgAFFAcJEgAfAHwTAA==.Spinach:BAAALgAECgYJEQAAAA==.Spire:BAAALgAECgYJEQAAAA==.Splithoofe:BAAALgAECgUJBQABLgAFFAIJBQANAMMFAA==.Sprawl:BAABLgAECn8VAAInAAYJxxFSAgAaAQAnAAYJxxFSAgAaAQAAAA==.',
Sq='Squrrlydan:BAAALgAECgYJEgAAAA==.',
St='Staint:BAAALgAECgYJEQAAAA==.Starnights:BAAALgAECgYJEgAAAA==.Statman:BAABLgAECn8WAAIhAAgJRguaBgAzAQAhAAgJRguaBgAzAQAAAA==.Steelbubble:BAAALgAECgYJDwAAAA==.Stengah:BAABLgAECn8VAAIiAAYJoCMRAQByAgAiAAYJoCMRAQByAgAAAA==.Steris:BAAALgADCgYJBgAAAA==.Strela:BAAALgAECggJIwAAAQ==.Stressummon:BAAALgADCgMJAgAAAA==.Strykie:BAAALgADCgQJBAAAAA==.',
Su='Sulina:BAAALgAECgMJAwAAAA==.',
Sw='Swtblsphmy:BAABLgAECn8aAAIRAAgJTBC5LQDTAQARAAgJTBC5LQDTAQAAAA==.',
Sy='Symphony:BAAALgADCgEJAQAAAA==.Syradora:BAAALgAECgMJBgAAAA==.Syynner:BAAALgAECgcJBwAAAA==.',
['Sè']='Sèd:BAAALgADCgcJDAAAAA==.',
Ta='Taelak:BAAALgAECgMJAwAAAA==.Tahrin:BAABLgAECn8VAAINAAgJkhhXFgCFAgANAAgJkhhXFgCFAgAAAA==.Talamon:BAAALgAECgYJEwAAAA==.Talmøre:BAAALgADCgMJAwAAAA==.Talyyon:BAAALgAECgMJBwAAAA==.Tandinise:BAAALgAECgYJBgAAAA==.Tandruid:BAAALgAECgMJBgABLgAECggJGgAIAAggAA==.Tanmonk:BAAALgAECgQJBAABLgAECggJGgAIAAggAA==.Tas:BAAALgADCgIJAgAAAA==.Tashi:BAABLgAECn8XAAICAAcJlxMnAwCIAQACAAcJlxMnAwCIAQAAAA==.Tasina:BAAALgAECgEJAQABLgAECgUJCAAGAAAAAA==.Tastictank:BAAALgAECgQJBgAAAA==.Taurenamos:BAABLgAECn8VAAQDAAYJvhMNQQAtAQADAAUJBhYNQQAtAQAEAAQJDgz4kACuAAAoAAYJ4AaACQCGAAAAAA==.Taynam:BAAALgAECgYJBgABLgAECgcJCwAGAAAAAA==.',
Te='Tebas:BAAALgAECgQJBQAAAA==.Teival:BAABLgAECn8XAAINAAgJKRfSBQAUAgANAAgJKRfSBQAUAgAAAA==.Tempëst:BAAALgADCgIJAgAAAA==.Tenchu:BAAALgAECgYJCwAAAA==.Tenfour:BAAALgADCgYJBgAAAA==.Tenseven:BAAALgAECgYJDwAAAA==.Teredorn:BAAALgADCgkJCgABLgAECgkJHQAeAMwbAA==.Terrorbláde:BAAALgADCgcJBwAAAA==.Terrørßlade:BAAALgADCgYJBgAAAA==.',
Th='Thalion:BAAALgADCgcJCQAAAA==.Thark:BAAALgAECgIJAQABLgAECgYJGAAQABAlAA==.Therris:BAAALgAECgYJEgAAAA==.Thidias:BAAALgAECgIJAgAAAA==.Thorimane:BAAALgAECgQJAwABLgAECgYJEgAGAAAAAA==.Thrizzowd:BAAALgADCgkJDQAAAA==.Throwd:BAABLgAECn8ZAAIcAAYJZhLdCgAmAQAcAAYJZhLdCgAmAQAAAA==.Thwark:BAAALgADCgQJBAABLgAECgYJGAAQABAlAA==.',
Ti='Tinytony:BAABLgAECn8UAAMjAAgJvxOdEgCgAQAjAAcJ4hWdEgCgAQAMAAMJyA2d8QCuAAAAAA==.',
To='Toranis:BAAALgADCgkJDwAAAA==.Torrellan:BAAALgADCgMJAwAAAA==.Torrents:BAABLgAECn8aAAQRAAYJHyMZGwA/AgARAAYJHyMZGwA/AgAlAAUJZhIzGACyAAApAAIJAQczJwBnAAAAAA==.Touchofchaos:BAAALgADCgYJBQAAAA==.Toxíc:BAAALgADCgcJEgAAAA==.',
Tr='Traffyfu:BAAALgAECgMJAwAAAA==.Traver:BAAALgAECgQJBAAAAA==.Trinytee:BAAALgADCgUJCQAAAA==.',
Tu='Ture:BAAALgADCgkJGQAAAA==.Turnandburn:BAAALgAECgEJAQAAAA==.',
Tw='Twistedsugar:BAAALgAECgMJAwAAAA==.Twìztid:BAABLgAECn8bAAILAAgJbSNlAgCTAgALAAgJbSNlAgCTAgAAAA==.',
Ty='Tyriäel:BAABLgAECn8eAAIZAAgJEx9/AQA2AgAZAAgJEx9/AQA2AgAAAA==.Tyrrible:BAAALgADCggJDwAAAA==.',
['Tà']='Tàyla:BAAALgADCgUJBQABLgADCgUJCQAGAAAAAA==.',
['Tð']='Tðxîc:BAAALgAECgEJAQAAAA==.',
Ul='Ulther:BAAALgAECgMJAwAAAA==.Ultìmecia:BAAALgAECgYJAQAAAA==.',
Un='Unbinddeath:BAAALgADCgQJBAAAAA==.Unfriendly:BAAALgADCgEJAQAAAA==.',
Up='Upside:BAAALgAECgUJBwAAAA==.',
Ur='Uruz:BAABLgAECn8bAAIFAAgJ3h9XGQCBAgAFAAgJ3h9XGQCBAgAAAA==.',
Ut='Uthêr:BAAALgADCgMJAwAAAA==.',
Va='Vacare:BAAALgAECgMJAwAAAA==.Valdyria:BAAALgADCgMJAwAAAA==.Valefar:BAAALgADCgYJDAAAAA==.Valkoienne:BAAALgAECgEJAQAAAA==.Valyniss:BAAALgADCgEJAQAAAA==.Vamp:BAAALgADCgUJBQAAAA==.Vanart:BAAALgAECgkJBQAAAA==.Vandemar:BAAALgAECgMJAwAAAA==.Vanderpump:BAAALgADCgYJBgABLgAECgkJGQAKAJsGAA==.Vanreu:BAAALgAECgYJBwAAAA==.Vavictus:BAAALgAECgMJAwAAAA==.',
Ve='Vedronorael:BAAALgADCgkJFgAAAA==.Vekkar:BAAALgADCgIJAgAAAA==.Velanthia:BAAALgAECgEJAQAAAA==.Vengrath:BAABLgAECn8VAAIVAAYJGiMZDADwAQAVAAYJGiMZDADwAQAAAA==.Venomgodd:BAAALgADCgEJAQAAAA==.Verderben:BAAALgAECgUJBQAAAA==.',
Vi='Vilenia:BAAALgAECgcJEwAAAA==.Vilkasdk:BAAALgAECgYJCQAAAA==.Vinchenzo:BAAALgAECgEJAQAAAA==.Vinhelsin:BAAALgADCgcJFwAAAA==.Violetangel:BAAALgAECgYJBQAAAA==.Vionir:BAABLgAECn8UAAIBAAcJ4SHxBQCoAgABAAcJ4SHxBQCoAgAAAA==.Vitality:BAAALgAECgIJAgAAAA==.',
Vo='Voidrush:BAAALgAECgMJAwAAAA==.Voirdire:BAAALgAECgYJCQAAAA==.Voron:BAAALgAECgYJCAAAAA==.',
Vu='Vulpa:BAABLgAECn8eAAMJAAcJ1hAHBAAgAQAJAAcJ1hAHBAAgAQAIAAIJFAJxDwE/AAAAAA==.',
Vy='Vynessa:BAAALgADCgkJFAAAAA==.Vyshareth:BAAALgADCgcJBwAAAA==.',
Wa='Wanren:BAAALgAECgQJBAAAAA==.Wargodd:BAAALgADCgMJAwAAAA==.Waterwhip:BAAALgAFFAIJAwAAAA==.',
We='Westfall:BAABLgAECn8UAAMZAAgJ6BwaDQA+AgAZAAgJ6BwaDQA+AgAYAAEJkwEJOQEfAAAAAA==.',
Wh='Whirl:BAAALgAECgQJCgABLgAECgcJGQAFALAZAA==.Whirlock:BAAALgADCgYJBgAAAA==.Whirlwind:BAABLgAECn8ZAAIFAAcJsBlEKgAQAgAFAAcJsBlEKgAQAgAAAA==.Whydoiexist:BAABLgAECn8VAAIdAAYJHCAEHQAbAgAdAAYJHCAEHQAbAgABLgAECgcJDgAGAAAAAA==.',
Wi='Willrun:BAAALgAECgQJCgAAAA==.Windwatcher:BAAALgAECgUJEAAAAA==.',
Wo='Wompeal:BAABLgAECn8dAAIOAAgJXR63CADAAgAOAAgJXR63CADAAgAAAA==.Wonkwonk:BAAALgAECgYJDQAAAA==.Worth:BAAALgAECggJEwAAAA==.',
Wr='Wrathofdirt:BAAALgADCgUJBQAAAA==.Wravin:BAABLgAECn8eAAINAAgJBw/RDwCDAQANAAgJBw/RDwCDAQABLgAECggJHgAOAFAOAA==.Wrukolas:BAAALgAECgYJEQAAAA==.',
Wu='Wulf:BAAALgADCgIJAgAAAA==.Wumdaorm:BAAALgADCgEJAQAAAA==.',
Wy='Wyhm:BAAALgADCgUJBwAAAA==.Wystan:BAABLgAECn8aAAIRAAYJThbHDQBiAQARAAYJThbHDQBiAQAAAA==.',
['Wé']='Wés:BAABLgAECn8YAAIdAAYJixZNCgBKAQAdAAYJixZNCgBKAQAAAA==.',
['Wí']='Wíckedwítch:BAAALgAECgcJCAAAAA==.',
Xa='Xalatoes:BAAALgADCgEJAgAAAA==.Xanthe:BAAALgAECgYJEQAAAA==.Xayden:BAAALgADCgMJAwAAAA==.',
Xe='Xeal:BAAALgAECgYJEQAAAA==.Xelkath:BAAALgAECgUJCwAAAA==.Xenomorphic:BAACLgAFFH8IAAISAAQJ/xVvBAApAQASAAQJ/xVvBAApAQAuAAQKfx8AAhIACQkXIkAAAGgDABIACQkXIkAAAGgDAAAA.Xentow:BAAALgAECgYJEgAAAA==.',
Xu='Xuanfeng:BAAALgAECgYJCwAAAA==.',
Xy='Xythros:BAAALgADCggJCAAAAA==.',
Ya='Yacob:BAAALgADCgEJAgABLgAECggJEQAGAAAAAA==.Yamling:BAAALgADCgkJGgAAAA==.Yarel:BAACLgAFFH8JAAISAAUJxwdPBgBjAQASAAUJxwdPBgBjAQAuAAQKfx4AAxIACQmiGf4NAHcCABIACQmiGf4NAHcCABMABAnBF4s3AEABAAEuAAUUAgkCAAYAAAAA.Yayaka:BAAALgAECgQJCAAAAA==.',
Yi='Yizdano:BAABLgAECn8WAAMcAAYJjhqdKQCuAQAcAAYJjhqdKQCuAQAbAAEJaxRqHQBAAAAAAA==.',
Yo='Yoloscrap:BAAALgADCgYJBQAAAA==.',
Yu='Yukiina:BAAALgADCgkJIAAAAA==.',
['Yù']='Yùm:BAAALgAECgUJBQABLgAECgkJJwAVAJUcAA==.',
Za='Zaccheus:BAAALgAECgYJCgAAAA==.Zalruin:BAAALgADCgkJCgAAAA==.Zambora:BAAALgADCgcJEwAAAA==.Zarb:BAAALgADCggJCAAAAA==.',
Ze='Zeebra:BAAALgAECgQJCgAAAA==.Zeenii:BAAALgADCgMJAwAAAA==.Zeesaw:BAABLgAECn8XAAMFAAcJcBw/BgDCAQAFAAcJcBw/BgDCAQAaAAEJWxPJPQA8AAAAAA==.Zeretrix:BAABLgAECn8eAAIVAAgJLhgkDADvAQAVAAgJLhgkDADvAQAAAA==.Zeroperfect:BAAALgADCgUJBQAAAA==.',
Zi='Zikà:BAAALgADCgMJAwAAAA==.Zinni:BAAALgADCgIJAgAAAA==.Ziros:BAAALgAECgYJBQAAAA==.',
Zl='Zlutar:BAAALgAECgMJBQAAAA==.',
Zo='Zoerisaya:BAAALgAECgQJCQAAAA==.',
Zy='Zynos:BAABLgAECn8ZAAILAAYJ1QsvJADxAAALAAYJ1QsvJADxAAAAAA==.',
['Ãl']='Ãlexstrasza:BAAALgADCgUJAwAAAA==.',
['Ça']='Çalindrel:BAAALgADCgkJCQAAAA==.',
['Ñu']='Ñuk:BAAALgAECgUJBQAAAA==.',
['Úà']='Úà:BAAALgADCgcJCgAAAA==.',
['Üb']='Überhealz:BAAALgAECgMJAwABLgAECgYJCgAGAAAAAA==.',
['ßö']='ßöw:BAABLgAECn8XAAMNAAYJ0gpicAAXAQANAAYJ2whicAAXAQACAAYJZghgWQDfAAAAAA==.',
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
